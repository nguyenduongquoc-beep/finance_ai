function createHttpError(statusCode, message, extra = {}) {
  const err = new Error(message);
  err.statusCode = statusCode;
  Object.assign(err, extra);
  return err;
}

function sendErrorResponse(res, error, fallbackMessage) {
  const code = error && error.statusCode ? error.statusCode : 500;
  const body = {
    error: (error && error.message) || fallbackMessage || "Lỗi xử lý phía máy chủ.",
  };
  if (error && Array.isArray(error.validationErrors) && error.validationErrors.length > 0) {
    body.validationErrors = error.validationErrors;
  }
  res.status(code).json(body);
}

/**
 * Chuẩn hóa danh sách origin hợp lệ từ biến môi trường (phân tách bởi dấu phẩy).
 * Tuyệt đối bỏ qua wildcard `*` và các chuỗi không đúng chuẩn origin HTTP(S).
 */
function parseAllowedAdminOrigins(allowedOriginsEnv = "") {
  const result = new Set();
  const rawList = String(allowedOriginsEnv || "").split(",");
  for (const rawItem of rawList) {
    const trimmed = rawItem.trim().replace(/\/+$/, "");
    if (!trimmed || trimmed === "*") continue;
    try {
      const parsed = new URL(trimmed);
      if (
        (parsed.protocol === "http:" || parsed.protocol === "https:") &&
        parsed.origin === trimmed
      ) {
        result.add(parsed.origin);
      }
    } catch (_) {
      // Bỏ qua origin cấu hình sai cú pháp thay vì mở rộng phạm vi ngoài ý muốn
    }
  }
  return Array.from(result);
}

/**
 * Kiểm tra một HTTP Origin header có nằm trong allowlist của Admin Portal hay không.
 * Hỗ trợ `ADMIN_ALLOWED_ORIGINS` (chuẩn URL origin) và localhost/127.0.0.1 cho môi trường dev.
 */
function isAllowedAdminOrigin(
  originHeader,
  {
    allowedOriginsEnv = process.env.ADMIN_ALLOWED_ORIGINS || "",
    allowLocalhost = process.env.ADMIN_ALLOW_LOCALHOST_CORS !== "false",
  } = {}
) {
  if (typeof originHeader !== "string" || !originHeader.trim()) {
    return { valid: false, allowed: false, normalizedOrigin: "", matchedBy: "missing" };
  }
  const trimmed = originHeader.trim().replace(/\/+$/, "");
  if (!trimmed || trimmed === "*" || trimmed.toLowerCase() === "null") {
    return { valid: false, allowed: false, normalizedOrigin: "", matchedBy: "invalid" };
  }

  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch (_) {
    return { valid: false, allowed: false, normalizedOrigin: "", matchedBy: "invalid" };
  }

  if (
    (parsed.protocol !== "http:" && parsed.protocol !== "https:") ||
    parsed.origin !== trimmed
  ) {
    return { valid: false, allowed: false, normalizedOrigin: "", matchedBy: "invalid" };
  }

  const configuredOrigins = parseAllowedAdminOrigins(allowedOriginsEnv);
  if (configuredOrigins.includes(parsed.origin)) {
    return {
      valid: true,
      allowed: true,
      normalizedOrigin: parsed.origin,
      matchedBy: "env_allowlist",
    };
  }

  if (
    allowLocalhost &&
    (parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1")
  ) {
    return {
      valid: true,
      allowed: true,
      normalizedOrigin: parsed.origin,
      matchedBy: "localhost_dev",
    };
  }

  return {
    valid: true,
    allowed: false,
    normalizedOrigin: parsed.origin,
    matchedBy: "denied",
  };
}

/**
 * Áp dụng chính sách CORS an toàn cho Admin Cloud Functions (không dùng `*`).
 * - CORS KHÔNG thay thế cơ chế xác thực Bearer ID Token + Admin Claims/Firestore ở backend.
 * - Request không gửi `Origin` (mobile native/server/CLI) vẫn đi qua bình thường
 *   (không cấp `Access-Control-Allow-Origin`) và phải tự vượt qua `verifyAdminCaller`.
 * - Request từ trình duyệt có `Origin` nằm trong allowlist được phản hồi chính xác
 *   origin đó kèm header `Authorization`, `X-Firebase-AppCheck`.
 * - Origin lạ bị từ chối với HTTP 403 và KHÔNG được cấp `Access-Control-Allow-Origin`.
 */
function applyAdminCorsPolicy(
  req,
  res,
  {
    allowedOriginsEnv = process.env.ADMIN_ALLOWED_ORIGINS || "",
    allowLocalhost = process.env.ADMIN_ALLOW_LOCALHOST_CORS !== "false",
  } = {}
) {
  const setHeader = (name, value) => {
    if (typeof res.set === "function") {
      res.set(name, value);
    } else if (typeof res.setHeader === "function") {
      res.setHeader(name, value);
    }
  };

  setHeader("Vary", "Origin");

  const method = String((req && req.method) || "GET").toUpperCase();
  const originHeader =
    req && req.headers ? req.headers.origin || req.headers.Origin || "" : "";

  if (!originHeader || !String(originHeader).trim()) {
    if (method === "OPTIONS") {
      setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      setHeader(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization, X-Firebase-AppCheck"
      );
      res.status(204).send("");
      return true;
    }
    return false;
  }

  const check = isAllowedAdminOrigin(originHeader, {
    allowedOriginsEnv,
    allowLocalhost,
  });

  if (!check.allowed) {
    res.status(403).json({
      error: "Origin không được phép truy cập Admin Cloud Functions.",
    });
    return true;
  }

  setHeader("Access-Control-Allow-Origin", check.normalizedOrigin);
  setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck"
  );
  setHeader("Access-Control-Max-Age", "3600");

  if (method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

/**
 * Xác thực Firebase ID Token + hồ sơ Firestore ở Backend.
 * Bắt buộc tài khoản Admin phải có document `users/{uid}` tồn tại với `status === 'active'`
 * để đồng bộ chặt chẽ với Firestore Security Rules `isAdmin()`.
 * Bảo toàn toàn bộ Custom Claims sẵn có khi tự động đồng bộ `{ admin: true }`.
 */
async function verifyAdminCallerWithDeps({
  req,
  db,
  auth,
  verifyAppCheckFn = async () => {},
  logger = console,
}) {
  await verifyAppCheckFn(req);
  const authHeader = (req && req.headers && req.headers.authorization) || "";
  if (!authHeader.startsWith("Bearer ")) {
    throw createHttpError(401, "Thiếu Firebase ID Token xác thực.");
  }

  const idToken = authHeader.substring("Bearer ".length).trim();
  if (!idToken) {
    throw createHttpError(401, "Firebase ID Token bị rỗng.");
  }

  let decoded;
  try {
    decoded = await auth.verifyIdToken(idToken, true);
  } catch (e) {
    throw createHttpError(401, "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.");
  }

  const adminUserDoc = await db.collection("users").doc(decoded.uid).get();
  if (!adminUserDoc.exists) {
    throw createHttpError(
      403,
      "Truy cập bị từ chối: Không tìm thấy hồ sơ users/{uid} hợp lệ cho tài khoản quản trị."
    );
  }
  const userData = adminUserDoc.data() || {};

  if (userData.status === "locked") {
    throw createHttpError(403, "Tài khoản quản trị viên này đã bị khóa.");
  }
  if (userData.status !== "active") {
    throw createHttpError(
      403,
      "Truy cập bị từ chối: Tài khoản quản trị viên không ở trạng thái active."
    );
  }

  const hasClaim = decoded.admin === true;
  const hasFirestoreRole = userData.role === "admin";

  // Bắt buộc `users/{uid}.role === 'admin'` song hành `status === 'active'`:
  // không cho phép token cũ còn `admin: true` vượt qua khi quyền Admin đã bị hạ về `user`.
  if (!hasFirestoreRole) {
    throw createHttpError(
      403,
      "Truy cập bị từ chối: Tài khoản không có quyền Quản trị viên (Admin)."
    );
  }

  // Bảo toàn Custom Claims cũ khi đồng bộ claim admin=true từ Firestore role
  let claimsSynced = false;
  if (!hasClaim && hasFirestoreRole) {
    try {
      const userRecord = await auth.getUser(decoded.uid);
      const mergedClaims = {
        ...(userRecord && userRecord.customClaims ? userRecord.customClaims : {}),
        admin: true,
      };
      await auth.setCustomUserClaims(decoded.uid, mergedClaims);
      claimsSynced = true;
    } catch (claimErr) {
      if (logger && typeof logger.warn === "function") {
        logger.warn("Không thể đồng bộ Custom Claim tự động:", claimErr);
      }
    }
  }

  return {
    uid: decoded.uid,
    email: decoded.email || userData.email || "",
    name: userData.name || decoded.name || "",
    role: "admin",
    status: userData.status || "active",
    hasAdminClaim: hasClaim || claimsSynced,
    hasFirestoreRole: true,
    claimsSynced: claimsSynced,
  };
}

/**
 * Bảo vệ Quản trị viên đang hoạt động cuối cùng của hệ thống.
 * Chặn thao tác khóa, hạ quyền hoặc xóa nếu `targetUid` là tài khoản
 * `role == 'admin' && status == 'active'` duy nhất còn lại.
 */
async function assertNotLastActiveAdmin(db, targetUid, targetData, tx = null) {
  const isTargetActiveAdmin =
    Boolean(targetData) &&
    targetData.role === "admin" &&
    targetData.status === "active";
  if (!isTargetActiveAdmin) return;

  const activeAdminsQuery = db
    .collection("users")
    .where("role", "==", "admin")
    .where("status", "==", "active")
    .limit(2);

  const snap = tx ? await tx.get(activeAdminsQuery) : await activeAdminsQuery.get();
  const docs = (snap && snap.docs) || [];
  const hasOtherActiveAdmin = docs.some((doc) => doc.id !== targetUid);

  if (!hasOtherActiveAdmin) {
    throw createHttpError(
      400,
      "Không thể khóa, hạ quyền hoặc xóa Quản trị viên đang hoạt động cuối cùng của hệ thống."
    );
  }
}

/**
 * Danh sách các root collection trong Firestore có dữ liệu thuộc về người dùng (qua trường `userId`).
 * Lưu ý: `support_tickets` (kèm subcollection `messages`) được dọn riêng bằng `deleteSupportTicketsInBatches`.
 */
const USER_OWNED_COLLECTIONS = Object.freeze([
  "wallets",
  "categories",
  "transactions",
  "budgets",
  "savingGoals",
  "monthly_plans",
  "notifications",
  "recurringTransactions",
  "recurringTransactionOccurrences",
  "chat_sessions",
]);

/**
 * Danh sách các subcollection con trực thuộc `users/{uid}` (dùng làm fallback khi môi trường
 * không có `db.recursiveDelete`, ví dụ FakeFirestore trong Unit Test).
 */
const USER_SUBCOLLECTIONS = Object.freeze([
  "quickTemplates",
  "chat_sessions",
  "monthly_plans",
]);

const USER_DELETION_MARKERS_COLLECTION = "_user_deletion_markers";
const ADMIN_DELETION_MARKER_TTL_MS = 15 * 60 * 1000;

/**
 * Xóa các documents theo query Firestore theo từng batch để không vượt quá giới hạn 500 writes/batch.
 */
async function deleteQueryInBatches(db, query, batchSize = 400) {
  let totalDeleted = 0;
  while (true) {
    const snapshot = await query.limit(batchSize).get();
    if (!snapshot || snapshot.empty || (snapshot.docs && snapshot.docs.length === 0)) {
      break;
    }
    const docs = snapshot.docs || [];
    if (typeof db.batch === "function") {
      const batch = db.batch();
      docs.forEach((doc) => {
        const ref = doc.ref || doc;
        batch.delete(ref);
      });
      await batch.commit();
    } else {
      for (const doc of docs) {
        if (doc.ref && typeof doc.ref.delete === "function") {
          await doc.ref.delete();
        } else if (typeof doc.delete === "function") {
          await doc.delete();
        }
      }
    }
    totalDeleted += docs.length;
    if (docs.length < batchSize) {
      break;
    }
  }
  return totalDeleted;
}

/**
 * Dọn sạch toàn bộ `support_tickets` thuộc `userId == uid` cùng toàn bộ subcollection `messages`
 * theo từng batch (an toàn với > 500 ticket và > 500 tin nhắn/ticket).
 */
async function deleteSupportTicketsInBatches(db, uid, batchSize = 400) {
  let ticketsDeleted = 0;
  let messagesDeleted = 0;
  const ticketsQuery = db.collection("support_tickets").where("userId", "==", uid);

  while (true) {
    const snapshot = await ticketsQuery.limit(batchSize).get();
    if (!snapshot || snapshot.empty || (snapshot.docs && snapshot.docs.length === 0)) {
      break;
    }
    const docs = snapshot.docs || [];

    for (const doc of docs) {
      const ref = doc.ref || db.collection("support_tickets").doc(doc.id);
      if (ref && typeof ref.collection === "function") {
        messagesDeleted += await deleteQueryInBatches(
          db,
          ref.collection("messages"),
          batchSize
        );
      }
    }

    if (typeof db.batch === "function") {
      const batch = db.batch();
      docs.forEach((doc) => {
        const ref = doc.ref || db.collection("support_tickets").doc(doc.id);
        batch.delete(ref);
      });
      await batch.commit();
    } else {
      for (const doc of docs) {
        const ref = doc.ref || db.collection("support_tickets").doc(doc.id);
        if (ref && typeof ref.delete === "function") {
          await ref.delete();
        }
      }
    }

    ticketsDeleted += docs.length;
    if (docs.length < batchSize) {
      break;
    }
  }

  return { ticketsDeleted, messagesDeleted };
}

/**
 * Hàm trung tâm dọn dẹp toàn bộ dữ liệu Firestore của một người dùng khi tài khoản bị xóa:
 * - Document `users/{uid}` và toàn bộ subcollections (`quickTemplates`, `chat_sessions`, `monthly_plans`)
 * - Mọi root collection thuộc `userId == uid` (chia batch <= 400 writes/batch)
 * - Toàn bộ `support_tickets` của user kèm subcollection `messages` (chia batch <= 400)
 * - Bản ghi OTP tạm thời `_otp_verifications/{email}`
 * - Ghi Audit Log hệ thống (chỉ khi `writeAuditLog === true`, KHÔNG ghi hay rò rỉ dữ liệu tài chính cá nhân).
 */
async function cleanupUserData({
  db,
  uid,
  email = null,
  deletedBy = "system",
  writeAuditLog = true,
  batchSize = 400,
  logger = console,
}) {
  const result = {
    uid,
    email: email || null,
    userDocDeleted: false,
    collectionsCleaned: {},
    supportMessagesCleaned: 0,
    otpCleaned: false,
    error: null,
  };

  try {
    const userDocRef = db.collection("users").doc(uid);
    let resolvedEmail = email;
    try {
      const userSnap = await userDocRef.get();
      if (!resolvedEmail && userSnap && userSnap.exists) {
        const data = typeof userSnap.data === "function" ? userSnap.data() : userSnap.data;
        resolvedEmail = (data && data.email) || null;
      }
    } catch (_) {}
    result.email = resolvedEmail || null;

    // 1. Xóa hồ sơ users/{uid} và toàn bộ subcollections (quickTemplates, chat_sessions, monthly_plans...)
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(userDocRef);
      result.userDocDeleted = true;
    } else {
      if (typeof userDocRef.collection === "function") {
        for (const subCol of USER_SUBCOLLECTIONS) {
          try {
            await deleteQueryInBatches(db, userDocRef.collection(subCol), batchSize);
          } catch (subErr) {
            if (logger && typeof logger.warn === "function") {
              logger.warn(`Lỗi dọn subcollection users/${uid}/${subCol}:`, subErr.message || subErr);
            }
          }
        }
      }
      if (typeof userDocRef.delete === "function") {
        await userDocRef.delete();
        result.userDocDeleted = true;
      }
    }

    // 2. Xóa các root collections có userId == uid theo batch
    for (const colName of USER_OWNED_COLLECTIONS) {
      try {
        const query = db.collection(colName).where("userId", "==", uid);
        const count = await deleteQueryInBatches(db, query, batchSize);
        result.collectionsCleaned[colName] = count;
      } catch (colErr) {
        if (logger && typeof logger.warn === "function") {
          logger.warn(`Lỗi dọn dẹp collection ${colName} cho user ${uid}:`, colErr.message || colErr);
        }
        result.collectionsCleaned[colName] = 0;
      }
    }

    // 3. Xóa support_tickets thuộc user kèm toàn bộ subcollection messages theo batch
    try {
      const supportRes = await deleteSupportTicketsInBatches(db, uid, batchSize);
      result.collectionsCleaned.support_tickets = supportRes.ticketsDeleted;
      result.supportMessagesCleaned = supportRes.messagesDeleted;
    } catch (supportErr) {
      if (logger && typeof logger.warn === "function") {
        logger.warn(`Lỗi dọn dẹp support_tickets cho user ${uid}:`, supportErr.message || supportErr);
      }
      result.collectionsCleaned.support_tickets = 0;
    }

    // 4. Xóa bản ghi OTP email nếu có
    if (resolvedEmail && typeof resolvedEmail === "string") {
      try {
        const cleanEmail = resolvedEmail.trim().toLowerCase();
        await db.collection("_otp_verifications").doc(cleanEmail).delete();
        result.otpCleaned = true;
      } catch (_) {}
    }

    // 5. Ghi Audit Log hệ thống (chỉ khi trigger Auth onDelete chạy độc lập, không lặp với adminDeleteUser)
    if (writeAuditLog) {
      try {
        const nowIso = new Date().toISOString();
        await db.collection("admin_logs").add({
          adminId: deletedBy,
          adminEmail: deletedBy === "system" ? "system@finance-ai.internal" : deletedBy,
          action: "CLEANUP_DELETED_AUTH_USER",
          targetType: "user",
          targetId: uid,
          targetLabel: resolvedEmail || uid,
          result: "success",
          details: `Đã dọn dẹp hoàn tất dữ liệu Firestore cho tài khoản ${resolvedEmail || uid} sau khi xóa trên Authentication.`,
          source: "cloud_function",
          createdAt: nowIso,
        });
      } catch (logErr) {
        if (logger && typeof logger.warn === "function") {
          logger.warn("Không thể ghi log admin_logs:", logErr.message || logErr);
        }
      }
    }

    return result;
  } catch (err) {
    if (logger && typeof logger.error === "function") {
      logger.error(`Lỗi nghiêm trọng khi dọn dẹp dữ liệu user ${uid}:`, err);
    }
    result.error = err.message || String(err);
    return result;
  }
}

/**
 * Handler cho Auth trigger `cleanupUserDataOnAuthDelete`.
 * Chống xung đột & chạy lặp khi tài khoản vừa bị xóa bởi `adminDeleteUser`:
 * nếu tồn tại marker `_user_deletion_markers/{uid}` còn hiệu lực, chỉ dọn marker và bỏ qua.
 */
async function handleAuthUserDeleteTrigger({
  db,
  user,
  logger = console,
  nowProvider = () => Date.now(),
}) {
  const uid = user && user.uid ? String(user.uid) : "";
  if (!uid) {
    return { skipped: true, reason: "missing_uid" };
  }

  const markerRef = db.collection(USER_DELETION_MARKERS_COLLECTION).doc(uid);
  try {
    const markerSnap = await markerRef.get();
    if (markerSnap && markerSnap.exists) {
      const markerData =
        typeof markerSnap.data === "function" ? markerSnap.data() : markerSnap.data;
      const createdAtMs = Number(markerData && markerData.createdAtMs);
      const isFresh =
        Number.isFinite(createdAtMs) &&
        nowProvider() - createdAtMs <= ADMIN_DELETION_MARKER_TTL_MS;
      await markerRef.delete().catch(() => {});
      if (markerData && markerData.initiatedBy === "adminDeleteUser" && isFresh) {
        if (logger && typeof logger.info === "function") {
          logger.info(
            `[cleanupUserDataOnAuthDelete] Bỏ qua dọn lặp cho UID ${uid} vì đã được xử lý đồng bộ bởi adminDeleteUser.`
          );
        }
        return {
          uid,
          skipped: true,
          reason: "handled_by_adminDeleteUser",
        };
      }
    }
  } catch (markerErr) {
    if (logger && typeof logger.warn === "function") {
      logger.warn(
        `[cleanupUserDataOnAuthDelete] Không đọc được marker cho UID ${uid}, tiếp tục dọn dẹp an toàn:`,
        markerErr.message || markerErr
      );
    }
  }

  return cleanupUserData({
    db,
    uid,
    email: user.email || null,
    deletedBy: "system",
    writeAuditLog: true,
    logger,
  });
}

function createAdminEndpointHandlers({
  db,
  auth,
  verifyAppCheckFn = async () => {},
  logger = console,
  nowProvider = () => Date.now(),
}) {
  const verifyCaller = (req) =>
    verifyAdminCallerWithDeps({
      req,
      db,
      auth,
      verifyAppCheckFn,
      logger,
    });

  async function adminVerifySession(req, res) {
    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      res.status(200).json({
        success: true,
        verifiedByServer: true,
        uid: caller.uid,
        email: caller.email,
        name: caller.name,
        role: caller.role,
        status: caller.status,
        hasAdminClaim: caller.hasAdminClaim,
        hasFirestoreRole: caller.hasFirestoreRole,
        claimsSynced: caller.claimsSynced,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminVerifySession:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể xác minh phiên Quản trị viên.");
    }
  }

  async function adminListUsers(req, res) {
    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      await verifyCaller(req);
      const snap = await db.collection("users").get();
      const users = (snap.docs || []).map((doc) => {
        const d = (typeof doc.data === "function" ? doc.data() : doc.data) || {};
        const rawCreatedAt = d.createdAt || null;
        const normalizedCreatedAt =
          rawCreatedAt && typeof rawCreatedAt.toDate === "function"
            ? rawCreatedAt.toDate().toISOString()
            : rawCreatedAt;
        // Zero-Knowledge Privacy: CHỈ trả 7 trường hồ sơ phi tài chính,
        // tuyệt đối không trả monthlyIncome, savingGoal, monthlyPlans hay dữ liệu riêng tư.
        return {
          uid: doc.id,
          name: d.name || "",
          email: d.email || "",
          role: d.role || "user",
          status: d.status || "active",
          occupation: d.occupation || null,
          createdAt: normalizedCreatedAt,
        };
      });

      res.status(200).json({
        success: true,
        users: users,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminListUsers:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể lấy danh sách tài khoản.");
    }
  }

  async function adminSetUserStatus(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { targetUid, status, reason } = req.body || {};

      if (!targetUid || typeof targetUid !== "string" || (status !== "active" && status !== "locked")) {
        throw createHttpError(400, "Tham số targetUid hoặc status không hợp lệ.");
      }

      if (targetUid === caller.uid) {
        throw createHttpError(400, "Quản trị viên không thể tự khóa tài khoản của chính mình.");
      }

      const isLocked = status === "locked";
      const targetDocRef = db.collection("users").doc(targetUid);
      const targetSnap = await targetDocRef.get();
      const targetData = targetSnap && targetSnap.exists
        ? (typeof targetSnap.data === "function" ? targetSnap.data() : targetSnap.data)
        : {};
      const targetEmail = (targetData && targetData.email) || targetUid;

      if (isLocked) {
        await assertNotLastActiveAdmin(db, targetUid, targetData);
      }

      // 1. Vô hiệu hóa hoặc khôi phục tài khoản trên Firebase Authentication (xử lý mềm user-not-found)
      let authUpdated = false;
      let previousAuthDisabled = null;
      if (auth && typeof auth.updateUser === "function") {
        try {
          if (typeof auth.getUser === "function") {
            const existingAuthUser = await auth.getUser(targetUid);
            previousAuthDisabled = Boolean(existingAuthUser && existingAuthUser.disabled);
          }
          await auth.updateUser(targetUid, { disabled: isLocked });
          authUpdated = true;
        } catch (authErr) {
          if (authErr && authErr.code === "auth/user-not-found") {
            if (logger && typeof logger.warn === "function") {
              logger.warn(
                `User ${targetUid} không tồn tại trên Authentication, tiếp tục đồng bộ trạng thái Firestore.`
              );
            }
          } else {
            throw createHttpError(
              500,
              `Không thể cập nhật trạng thái trên Authentication: ${authErr.message || authErr}`
            );
          }
        }
      }

      // 2. Cập nhật trạng thái trên Firestore trong transaction (kiểm tra lại Admin cuối cùng & rollback Auth nếu lỗi)
      const nowIso = new Date(nowProvider()).toISOString();
      try {
        if (typeof db.runTransaction === "function") {
          await db.runTransaction(async (tx) => {
            const latestSnap = await tx.get(targetDocRef);
            const latestData = latestSnap && latestSnap.exists
              ? (typeof latestSnap.data === "function" ? latestSnap.data() : latestSnap.data)
              : targetData;
            if (isLocked) {
              await assertNotLastActiveAdmin(db, targetUid, latestData, tx);
            }
            await tx.set(
              targetDocRef,
              {
                status: status,
                updatedAt: nowIso,
              },
              { merge: true }
            );
          });
        } else {
          await targetDocRef.set(
            {
              status: status,
              updatedAt: nowIso,
            },
            { merge: true }
          );
        }
      } catch (firestoreErr) {
        if (authUpdated && auth && typeof auth.updateUser === "function") {
          const rollbackDisabled =
            previousAuthDisabled !== null ? previousAuthDisabled : !isLocked;
          try {
            await auth.updateUser(targetUid, { disabled: rollbackDisabled });
          } catch (rbErr) {
            if (logger && typeof logger.error === "function") {
              logger.error(`Rollback Auth disabled cho ${targetUid} thất bại:`, rbErr);
            }
          }
        }
        throw firestoreErr;
      }

      if (isLocked && authUpdated && auth && typeof auth.revokeRefreshTokens === "function") {
        await auth.revokeRefreshTokens(targetUid);
      }

      // 3. Ghi nhật ký quản trị sau khi thao tác thực tế thành công
      const cleanReason = typeof reason === "string" ? reason.trim() : "";
      const actionCode = isLocked ? "LOCK_USER" : "UNLOCK_USER";
      const logRef = await db.collection("admin_logs").add({
        adminId: caller.uid,
        adminEmail: caller.email,
        action: actionCode,
        targetType: "user",
        targetId: targetUid,
        targetLabel: targetEmail,
        result: "success",
        details: cleanReason
          ? `${isLocked ? "Khóa" : "Mở khóa"} tài khoản ${targetEmail}. Lý do: ${cleanReason}`
          : `${isLocked ? "Khóa" : "Mở khóa"} tài khoản ${targetEmail} (Đồng bộ Firebase Auth & Firestore).`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      res.status(200).json({
        success: true,
        targetUid: targetUid,
        status: status,
        authDisabled: authUpdated ? isLocked : false,
        authUpdated: authUpdated,
        logId: logRef.id,
        message: isLocked
          ? `Đã khóa tài khoản ${targetEmail} trên Firebase Auth và Firestore.`
          : `Đã mở khóa tài khoản ${targetEmail}.`,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminSetUserStatus:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật trạng thái tài khoản.");
    }
  }

  async function adminSetUserRole(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { targetUid, role } = req.body || {};

      if (!targetUid || (role !== "user" && role !== "admin")) {
        throw createHttpError(400, "Tham số targetUid hoặc role không hợp lệ.");
      }

      if (targetUid === caller.uid && role !== "admin") {
        throw createHttpError(400, "Không thể tự thu hồi quyền Admin của chính mình.");
      }

      const isAdminRole = role === "admin";
      const targetDocRef = db.collection("users").doc(targetUid);
      const targetSnap = await targetDocRef.get();
      const targetData = targetSnap && targetSnap.exists
        ? (typeof targetSnap.data === "function" ? targetSnap.data() : targetSnap.data)
        : {};
      const targetEmail = (targetData && targetData.email) || targetUid;

      if (!isAdminRole) {
        await assertNotLastActiveAdmin(db, targetUid, targetData);
      }

      // 1. Cập nhật Custom Claims NHƯNG luôn bảo toàn các claims khác hiện có trên tài khoản
      const existingUser = await auth.getUser(targetUid);
      const previousClaims =
        existingUser && existingUser.customClaims
          ? { ...existingUser.customClaims }
          : {};
      const mergedClaims = {
        ...previousClaims,
        admin: isAdminRole,
      };
      await auth.setCustomUserClaims(targetUid, mergedClaims);

      // 2. Đồng bộ role trên Firestore (kiểm tra lại Admin cuối cùng & rollback claims nếu lỗi)
      const nowIso = new Date(nowProvider()).toISOString();
      try {
        if (typeof db.runTransaction === "function") {
          await db.runTransaction(async (tx) => {
            const latestSnap = await tx.get(targetDocRef);
            const latestData = latestSnap && latestSnap.exists
              ? (typeof latestSnap.data === "function" ? latestSnap.data() : latestSnap.data)
              : targetData;
            if (!isAdminRole) {
              await assertNotLastActiveAdmin(db, targetUid, latestData, tx);
            }
            const preservedStatus =
              latestData && latestData.status ? latestData.status : "active";
            await tx.set(
              targetDocRef,
              {
                role: role,
                status: preservedStatus,
                updatedAt: nowIso,
              },
              { merge: true }
            );
          });
        } else {
          const preservedStatus =
            targetData && targetData.status ? targetData.status : "active";
          await targetDocRef.set(
            {
              role: role,
              status: preservedStatus,
              updatedAt: nowIso,
            },
            { merge: true }
          );
        }
      } catch (firestoreErr) {
        try {
          await auth.setCustomUserClaims(targetUid, previousClaims);
        } catch (rbErr) {
          if (logger && typeof logger.error === "function") {
            logger.error(`Rollback Custom Claims cho ${targetUid} thất bại:`, rbErr);
          }
        }
        throw firestoreErr;
      }

      // 3. Thu hồi ngay Refresh Token khi hạ quyền về 'user' để đóng khe hở JWT cũ 60 phút
      let tokensRevoked = false;
      if (!isAdminRole && typeof auth.revokeRefreshTokens === "function") {
        await auth.revokeRefreshTokens(targetUid);
        tokensRevoked = true;
      }

      // 4. Ghi nhật ký quản trị
      const logRef = await db.collection("admin_logs").add({
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "SET_USER_ROLE",
        targetType: "user",
        targetId: targetUid,
        targetLabel: targetEmail,
        result: "success",
        details: `Cập nhật quyền tài khoản ${targetEmail} thành ${role.toUpperCase()} (Custom Claim admin=${isAdminRole}${
          tokensRevoked ? ", đã thu hồi phiên cũ" : ""
        }).`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      res.status(200).json({
        success: true,
        targetUid: targetUid,
        role: role,
        tokensRevoked: tokensRevoked,
        logId: logRef.id,
        message: `Đã cập nhật quyền ${targetEmail} thành ${role.toUpperCase()}.`,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminSetUserRole:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật quyền tài khoản.");
    }
  }

  async function adminDeleteUser(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { targetUid, reason } = req.body || {};

      if (!targetUid || typeof targetUid !== "string") {
        throw createHttpError(400, "Tham số targetUid không hợp lệ.");
      }

      if (targetUid === caller.uid) {
        throw createHttpError(400, "Quản trị viên không thể tự xóa tài khoản của chính mình.");
      }

      const targetDocRef = db.collection("users").doc(targetUid);
      const targetSnap = await targetDocRef.get();
      const targetData = targetSnap && targetSnap.exists
        ? (typeof targetSnap.data === "function" ? targetSnap.data() : targetSnap.data)
        : {};
      const targetEmail = targetData.email || targetUid;

      // Chặn xóa Quản trị viên đang hoạt động cuối cùng của hệ thống
      await assertNotLastActiveAdmin(db, targetUid, targetData);

      const nowMs = nowProvider();
      const nowIso = new Date(nowMs).toISOString();

      // 1. Đánh dấu marker trước khi xóa trên Auth để trigger `cleanupUserDataOnAuthDelete`
      //    không chạy lặp và không ghi trùng Audit Log.
      const markerRef = db.collection(USER_DELETION_MARKERS_COLLECTION).doc(targetUid);
      let markerCreated = false;
      try {
        await markerRef.set({
          uid: targetUid,
          initiatedBy: "adminDeleteUser",
          createdAtMs: nowMs,
          createdAt: nowIso,
        });
        markerCreated = true;
      } catch (markerErr) {
        if (logger && typeof logger.warn === "function") {
          logger.warn("Không thể ghi deletion marker:", markerErr.message || markerErr);
        }
      }

      // 2. Xóa tài khoản trên Firebase Authentication
      let authDeleted = false;
      try {
        if (auth && typeof auth.deleteUser === "function") {
          await auth.deleteUser(targetUid);
          authDeleted = true;
        }
      } catch (authErr) {
        if (authErr && authErr.code !== "auth/user-not-found") {
          if (markerCreated) {
            await markerRef.delete().catch(() => {});
          }
          throw createHttpError(
            500,
            `Không thể xóa tài khoản trên Authentication: ${authErr.message || authErr}`
          );
        }
        if (logger && typeof logger.warn === "function") {
          logger.warn(`User ${targetUid} không tồn tại trên Authentication, tiếp tục dọn Firestore.`);
        }
      }

      // 3. Dọn dẹp toàn bộ dữ liệu Firestore theo batch (writeAuditLog=false vì bước 4 ghi ADMIN_DELETE_USER)
      const cleanupResult = await cleanupUserData({
        db,
        uid: targetUid,
        email: targetEmail,
        deletedBy: caller.email || caller.uid,
        writeAuditLog: false,
        logger,
      });

      // Nếu user không tồn tại trên Auth (trigger onDelete sẽ không bắn), tự dọn marker luôn
      if (markerCreated && !authDeleted) {
        await markerRef.delete().catch(() => {});
      }

      // 4. Ghi duy nhất 1 bản ghi Audit Log thao tác của Admin (kèm lý do xóa, không lộ dữ liệu tài chính)
      const cleanReason = typeof reason === "string" ? reason.trim() : "";
      const logRef = await db.collection("admin_logs").add({
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "ADMIN_DELETE_USER",
        targetType: "user",
        targetId: targetUid,
        targetLabel: targetEmail,
        result: "success",
        details: cleanReason
          ? `Quản trị viên đã xóa vĩnh viễn tài khoản ${targetEmail} (Auth + Firestore). Lý do: ${cleanReason}`
          : `Quản trị viên đã xóa vĩnh viễn tài khoản ${targetEmail} (Auth + Firestore).`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      // Nguyên tắc Zero-Knowledge Privacy: TUYỆT ĐỐI không trả dữ liệu/thống kê tài chính của User về Web Admin
      res.status(200).json({
        success: true,
        targetUid: targetUid,
        targetEmail: targetEmail,
        authDeleted: authDeleted,
        dataCleaned: !cleanupResult.error,
        logId: logRef.id,
        message: `Đã xóa vĩnh viễn tài khoản ${targetEmail} cùng toàn bộ dữ liệu liên quan.`,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminDeleteUser:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể xóa tài khoản người dùng.");
    }
  }

  /**
   * Quản trị Danh mục Hệ thống (`system_categories`) + Audit Log phía Server
   */
  async function adminManageSystemCategory(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { action, template, isNew, categoryId, isActive, categoryName, seedItems } =
        req.body || {};

      const nowIso = new Date(nowProvider()).toISOString();
      const col = db.collection("system_categories");

      if (action === "save") {
        if (!template || typeof template !== "object") {
          throw createHttpError(400, "Thiếu thông tin template danh mục hệ thống.");
        }
        const name = String(template.name || "").trim();
        const type = template.type === "income" ? "income" : "expense";
        const icon = String(template.icon || "category").trim();
        const color = Number(template.color);
        if (!name || name.length > 80 || Number.isNaN(color)) {
          throw createHttpError(400, "Tên hoặc màu sắc danh mục hệ thống không hợp lệ.");
        }

        const docRef =
          template.id && String(template.id).trim()
            ? col.doc(String(template.id).trim())
            : col.doc();

        const dataToSave = {
          id: docRef.id,
          name: name,
          type: type,
          icon: icon,
          color: Math.trunc(color),
          isEssential: template.isEssential === true,
          isActive: template.isActive !== false,
          createdAt: template.createdAt || nowIso,
          updatedAt: nowIso,
        };
        await docRef.set(dataToSave, { merge: true });

        const actionCode = isNew ? "CREATE_SYSTEM_CATEGORY" : "UPDATE_SYSTEM_CATEGORY";
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: actionCode,
          targetType: "system_category",
          targetId: docRef.id,
          targetLabel: name,
          result: "success",
          details: `${isNew ? "Tạo mới" : "Cập nhật"} danh mục hệ thống "${name}" (${type}, ${
            dataToSave.isEssential ? "Thiết yếu" : "Linh hoạt"
          }).`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          categoryId: docRef.id,
          logId: logRef.id,
        });
        return;
      }

      if (action === "toggle_active") {
        const id = String(categoryId || "").trim();
        if (!id || typeof isActive !== "boolean") {
          throw createHttpError(400, "Tham số categoryId hoặc isActive không hợp lệ.");
        }
        await col.doc(id).set(
          {
            isActive: isActive,
            updatedAt: nowIso,
          },
          { merge: true }
        );
        const label = String(categoryName || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isActive ? "SHOW_SYSTEM_CATEGORY" : "HIDE_SYSTEM_CATEGORY",
          targetType: "system_category",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: isActive
            ? `Hiển thị lại danh mục mẫu "${label}".`
            : `Ẩn danh mục mẫu "${label}" khỏi gợi ý tạo mới.`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          categoryId: id,
          isActive: isActive,
          logId: logRef.id,
        });
        return;
      }

      if (action === "seed_defaults") {
        if (!Array.isArray(seedItems) || seedItems.length === 0 || seedItems.length > 50) {
          throw createHttpError(400, "Danh sách seedItems không hợp lệ.");
        }
        for (const item of seedItems) {
          const itemId = String(item.id || "").trim();
          const itemName = String(item.name || "").trim();
          if (!itemId || !itemName) continue;
          await col.doc(itemId).set(
            {
              id: itemId,
              name: itemName,
              type: item.type === "income" ? "income" : "expense",
              icon: String(item.icon || "category"),
              color: Number.isFinite(Number(item.color)) ? Math.trunc(Number(item.color)) : 0xFF607D8B,
              isEssential: item.isEssential === true,
              isActive: true,
              createdAt: nowIso,
              updatedAt: nowIso,
            },
            { merge: true }
          );
        }
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: "SEED_SYSTEM_CATEGORIES",
          targetType: "system_category",
          targetId: "system_categories",
          targetLabel: `Bộ danh mục chuẩn (${seedItems.length} danh mục)`,
          result: "success",
          details: `Khởi tạo ${seedItems.length} danh mục mẫu mặc định cho hệ thống.`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          seededCount: seedItems.length,
          logId: logRef.id,
        });
        return;
      }

      throw createHttpError(400, 'Tham số action không hợp lệ (chỉ nhận save, toggle_active, seed_defaults).');
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminManageSystemCategory:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật danh mục hệ thống.");
    }
  }

  /**
   * Quản trị Thông báo Hệ thống (`system_announcements`) + Audit Log phía Server
   */
  async function adminManageAnnouncement(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { action, announcement, isNew, announcementId, isActive, title } = req.body || {};
      const nowIso = new Date(nowProvider()).toISOString();
      const col = db.collection("system_announcements");

      if (action === "save") {
        if (!announcement || typeof announcement !== "object") {
          throw createHttpError(400, "Thiếu dữ liệu announcement.");
        }
        const annTitle = String(announcement.title || "").trim();
        const annContent = String(
          announcement.content !== undefined
            ? announcement.content
            : announcement.message || ""
        ).trim();
        if (!annTitle || annTitle.length > 150 || !annContent || annContent.length > 1000) {
          throw createHttpError(400, "Tiêu đề hoặc nội dung thông báo hệ thống không hợp lệ.");
        }

        const docRef =
          announcement.id && String(announcement.id).trim()
            ? col.doc(String(announcement.id).trim())
            : col.doc();

        const existingSnap = await docRef.get();
        const existingData =
          existingSnap && existingSnap.exists
            ? (typeof existingSnap.data === "function"
                ? existingSnap.data()
                : existingSnap.data) || {}
            : null;
        const actorLabel = caller.email || caller.uid;
        const preservedCreatedBy =
          existingData && existingData.createdBy
            ? existingData.createdBy
            : announcement.createdBy || actorLabel;
        const preservedCreatedAt =
          existingData && existingData.createdAt
            ? existingData.createdAt
            : announcement.createdAt || nowIso;

        await docRef.set(
          {
            id: docRef.id,
            title: annTitle,
            content: annContent,
            isActive: announcement.isActive !== false,
            createdBy: preservedCreatedBy,
            updatedBy: actorLabel,
            createdAt: preservedCreatedAt,
            updatedAt: nowIso,
          },
          { merge: true }
        );

        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isNew ? "CREATE_ANNOUNCEMENT" : "UPDATE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: docRef.id,
          targetLabel: annTitle,
          result: "success",
          details: `${isNew ? "Tạo thông báo hệ thống mới" : "Cập nhật thông báo hệ thống"} "${annTitle}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: docRef.id,
          logId: logRef.id,
        });
        return;
      }

      if (action === "toggle_active") {
        const id = String(announcementId || "").trim();
        if (!id || typeof isActive !== "boolean") {
          throw createHttpError(400, "Tham số announcementId hoặc isActive không hợp lệ.");
        }
        const docRef = col.doc(id);
        const existingSnap = await docRef.get();
        if (!existingSnap || !existingSnap.exists) {
          throw createHttpError(404, "Không tìm thấy thông báo hệ thống cần cập nhật.");
        }
        const existingData =
          (typeof existingSnap.data === "function"
            ? existingSnap.data()
            : existingSnap.data) || {};

        await docRef.set(
          {
            isActive: isActive,
            updatedBy: caller.email || caller.uid,
            updatedAt: nowIso,
          },
          { merge: true }
        );
        const label = String(existingData.title || title || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isActive ? "ACTIVATE_ANNOUNCEMENT" : "DEACTIVATE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: isActive
            ? `Kích hoạt hiển thị thông báo "${label}".`
            : `Ngừng hiển thị thông báo "${label}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: id,
          isActive: isActive,
          logId: logRef.id,
        });
        return;
      }

      if (action === "delete") {
        const id = String(announcementId || "").trim();
        if (!id) {
          throw createHttpError(400, "Thiếu announcementId cần xóa.");
        }
        const docRef = col.doc(id);
        const existingSnap = await docRef.get();
        if (!existingSnap || !existingSnap.exists) {
          throw createHttpError(404, "Không tìm thấy thông báo hệ thống cần xóa.");
        }
        const existingData =
          (typeof existingSnap.data === "function"
            ? existingSnap.data()
            : existingSnap.data) || {};

        await docRef.delete();
        const label = String(existingData.title || title || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: "DELETE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: `Đã xóa thông báo hệ thống "${label}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: id,
          logId: logRef.id,
        });
        return;
      }

      throw createHttpError(400, 'Tham số action không hợp lệ (chỉ nhận save, toggle_active, delete).');
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminManageAnnouncement:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật thông báo hệ thống.");
    }
  }

  return {
    adminVerifySession,
    adminListUsers,
    adminSetUserStatus,
    adminSetUserRole,
    adminDeleteUser,
    adminManageSystemCategory,
    adminManageAnnouncement,
  };
}

module.exports = {
  USER_OWNED_COLLECTIONS,
  USER_SUBCOLLECTIONS,
  USER_DELETION_MARKERS_COLLECTION,
  deleteQueryInBatches,
  deleteSupportTicketsInBatches,
  cleanupUserData,
  handleAuthUserDeleteTrigger,
  createHttpError,
  parseAllowedAdminOrigins,
  isAllowedAdminOrigin,
  applyAdminCorsPolicy,
  verifyAdminCallerWithDeps,
  assertNotLastActiveAdmin,
  createAdminEndpointHandlers,
};
