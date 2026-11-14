const functions = require("firebase-functions");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");
const {
  ALLOWED_CONFIG_TYPES,
  computeCanonicalConfigHash,
  validateConfigPayloadServerSide,
  verifyAdminCallerWithDeps,
  createAdminEndpointHandlers,
} = require("./admin_helpers");

admin.initializeApp();
const db = admin.firestore();
const geminiApiKeySecret = defineSecret("GEMINI_API_KEY");

// ----------------------------------------------------------------------
// CẤU HÌNH GỬI EMAIL (GMAIL SMTP HOẶC DỊCH VỤ EMAIL TÙY CHỌN)
// Cấu hình qua biến môi trường (.env) hoặc Firebase Environment Config:
// EMAIL_USER="your-email@gmail.com" EMAIL_PASS="your-app-password"
// Tuyệt đối không ghi cứng thông tin xác thực trong mã nguồn.
// ----------------------------------------------------------------------
const EMAIL_USER = process.env.EMAIL_USER || functions.config().email?.user || "";
const rawPass = process.env.EMAIL_PASS || functions.config().email?.pass || "";
const EMAIL_PASS = rawPass.replace(/\s+/g, "");

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: EMAIL_USER,
    pass: EMAIL_PASS,
  },
});

const SALT = "FINANCE_AI_SECURE_SALT_2026";

function hashOtp(otp, email) {
  return crypto.createHash("sha256").update(`${email}:${otp}:${SALT}`).digest("hex");
}

/**
 * 1. Endpoint gửi mã OTP 6 số qua Email
 * POST /sendPasswordResetOtp
 * Body: { email: string }
 */
exports.sendPasswordResetOtp = functions.https.onRequest(async (req, res) => {
  // Cho phép CORS
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  const { email } = req.body;
  if (!email || typeof email !== "string" || !email.includes("@")) {
    res.status(400).json({ error: "Email không đúng định dạng." });
    return;
  }

  const cleanEmail = email.trim().toLowerCase();

  try {
    // 1. Kiểm tra tài khoản có tồn tại trong Firebase Authentication hay không
    let user;
    try {
      user = await admin.auth().getUserByEmail(cleanEmail);
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        res.status(404).json({
          error: "Không tìm thấy tài khoản với email này trên hệ thống.",
        });
        return;
      }
      throw err;
    }

    // 2. Chống gửi spam (Cooldown 60 giây)
    const otpDocRef = db.collection("_otp_verifications").doc(cleanEmail);
    const existingDoc = await otpDocRef.get();
    const now = Date.now();

    if (existingDoc.exists) {
      const data = existingDoc.data();
      if (data.resendAvailableAt && now < data.resendAvailableAt) {
        const remaining = Math.ceil((data.resendAvailableAt - now) / 1000);
        res.status(429).json({
          error: `Vui lòng đợi ${remaining} giây trước khi yêu cầu gửi lại mã.`,
          cooldownSeconds: remaining,
        });
        return;
      }
    }

    // 3. Sinh mã OTP 6 chữ số ngẫu nhiên an toàn (CSPRNG)
    const otpNumber = crypto.randomInt(100000, 999999).toString();
    const hashedOtp = hashOtp(otpNumber, cleanEmail);
    const expiresAt = now + 5 * 60 * 1000; // Hết hạn sau 5 phút
    const resendAvailableAt = now + 60 * 1000; // Cooldown 60s

    // 4. Lưu hash của OTP vào Firestore nội bộ
    await otpDocRef.set({
      email: cleanEmail,
      hashedOtp: hashedOtp,
      expiresAt: expiresAt,
      resendAvailableAt: resendAvailableAt,
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 5. Soạn thảo và gửi Email qua Nodemailer
    const mailOptions = {
      from: `"Finance AI App" <${EMAIL_USER}>`,
      to: cleanEmail,
      subject: `[Finance AI] Mã xác nhận đặt lại mật khẩu của bạn: ${otpNumber}`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 12px; background-color: #ffffff;">
          <div style="text-align: center; margin-bottom: 24px;">
            <h2 style="color: #1F6F8B; margin: 0;">Finance AI</h2>
            <p style="color: #64748b; font-size: 14px; margin-top: 4px;">Ứng dụng quản lý tài chính thông minh</p>
          </div>
          <p style="font-size: 15px; color: #1e293b;">Xin chào <strong>${user.displayName || "bạn"}</strong>,</p>
          <p style="font-size: 14px; color: #475569; line-height: 1.5;">
            Hệ thống nhận được yêu cầu đặt lại mật khẩu cho tài khoản <strong>${cleanEmail}</strong>. Mã xác minh OTP gồm 6 chữ số của bạn là:
          </p>
          <div style="text-align: center; margin: 28px 0;">
            <span style="display: inline-block; font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #1F6F8B; padding: 12px 24px; background-color: #f0f9ff; border: 1px dashed #0284c7; border-radius: 8px;">
              ${otpNumber}
            </span>
          </div>
          <p style="font-size: 13px; color: #64748b; line-height: 1.4;">
            • Mã xác minh có hiệu lực trong vòng <strong>5 phút</strong>.<br>
            • Tuyệt đối không chia sẻ mã này cho bất kỳ ai để bảo vệ an toàn tài khoản.
          </p>
          <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
          <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
            Nếu bạn không yêu cầu thay đổi mật khẩu, vui lòng bỏ qua thư này.
          </p>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);

    res.status(200).json({
      success: true,
      message: "Đã gửi mã xác nhận OTP gồm 6 chữ số đến email của bạn.",
      cooldownSeconds: 60,
    });
  } catch (error) {
    functions.logger.error("Lỗi gửi OTP:", error);
    res.status(500).json({
      error: "Không thể gửi email lúc này. Vui lòng kiểm tra lại cấu hình máy chủ.",
    });
  }
});

/**
 * 2. Endpoint xác thực mã OTP
 * POST /verifyOtp
 * Body: { email: string, otp: string }
 */
exports.verifyOtp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  const { email, otp } = req.body;
  if (!email || !otp || otp.length !== 6) {
    res.status(400).json({ error: "Dữ liệu xác thực không hợp lệ." });
    return;
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanOtp = otp.trim();

  try {
    const otpDocRef = db.collection("_otp_verifications").doc(cleanEmail);
    const doc = await otpDocRef.get();

    if (!doc.exists) {
      res.status(400).json({ error: "Yêu cầu OTP không tồn tại hoặc đã hết hạn." });
      return;
    }

    const data = doc.data();
    const now = Date.now();

    // Kiểm tra hết hạn (5 phút)
    if (now > data.expiresAt) {
      await otpDocRef.delete();
      res.status(400).json({ error: "Mã OTP đã hết thời hạn sử dụng. Vui lòng gửi lại mã mới." });
      return;
    }

    // Kiểm tra giới hạn nhập sai (Tối đa 5 lần)
    if ((data.attempts || 0) >= 5) {
      await otpDocRef.delete();
      res.status(429).json({ error: "Bạn đã nhập sai quá 5 lần. Yêu cầu đã bị hủy vì lý do bảo mật." });
      return;
    }

    // So sánh hash
    const inputHash = hashOtp(cleanOtp, cleanEmail);
    if (inputHash !== data.hashedOtp) {
      await otpDocRef.update({
        attempts: admin.firestore.FieldValue.increment(1),
      });
      res.status(400).json({ error: "Mã OTP không chính xác. Vui lòng kiểm tra lại." });
      return;
    }

    // Sinh reset token tạm thời có hạn 10 phút
    const resetToken = crypto.randomBytes(24).toString("hex");
    await otpDocRef.update({
      resetToken: resetToken,
      verified: true,
      tokenExpiresAt: now + 10 * 60 * 1000,
    });

    res.status(200).json({
      success: true,
      message: "Xác thực mã OTP thành công.",
      resetToken: resetToken,
    });
  } catch (error) {
    functions.logger.error("Lỗi verify OTP:", error);
    res.status(500).json({ error: "Lỗi máy chủ khi xác thực mã OTP." });
  }
});

/**
 * 3. Endpoint cập nhật mật khẩu mới qua Firebase Admin SDK
 * POST /resetPasswordWithOtp
 * Body: { email: string, otp: string, newPassword: string, resetToken: string }
 */
exports.resetPasswordWithOtp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  const { email, otp, newPassword, resetToken } = req.body;
  if (!email || !newPassword || newPassword.length < 6) {
    res.status(400).json({ error: "Mật khẩu mới phải có ít nhất 6 ký tự." });
    return;
  }

  const cleanEmail = email.trim().toLowerCase();

  try {
    const otpDocRef = db.collection("_otp_verifications").doc(cleanEmail);
    const doc = await otpDocRef.get();

    if (!doc.exists) {
      res.status(400).json({ error: "Phiên đặt lại mật khẩu đã hết hạn." });
      return;
    }

    const data = doc.data();

    // Xác thực token hoặc mã OTP
    const isTokenValid = resetToken && data.resetToken === resetToken && data.verified;
    const isOtpValid = otp && hashOtp(otp.trim(), cleanEmail) === data.hashedOtp;

    if (!isTokenValid && !isOtpValid) {
      res.status(403).json({ error: "Xác thực không hợp lệ hoặc phiên làm việc đã bị hủy." });
      return;
    }

    // Lấy UID từ Firebase Auth
    const user = await admin.auth().getUserByEmail(cleanEmail);

    // Dùng Firebase Admin SDK để cập nhật mật khẩu mới
    await admin.auth().updateUser(user.uid, {
      password: newPassword,
    });

    // Xóa bản ghi OTP để chống tái sử dụng
    await otpDocRef.delete();

    res.status(200).json({
      success: true,
      message: "Đặt lại mật khẩu thành công! Bạn có thể đăng nhập ngay.",
    });
  } catch (error) {
    functions.logger.error("Lỗi đặt lại mật khẩu:", error);
    res.status(500).json({ error: "Không thể cập nhật mật khẩu lúc này." });
  }
});

// ======================================================================
// CÁC CLOUD FUNCTIONS QUẢN TRỊ HỆ THỐNG (ADMIN WEB PORTAL)
// Bảo mật:
// 1. Xác thực Firebase ID Token qua Authorization: Bearer <token>.
// 2. Kiểm tra quyền Admin qua Custom Claims (token.admin === true)
//    hoặc hồ sơ Firestore (users/{uid}.role === 'admin') và tài khoản không bị khóa.
// 3. Không cho phép truy cập dữ liệu tài chính cá nhân (ví, giao dịch, ngân sách).
// 4. Ghi nhật ký quản trị (admin_logs) sau khi thao tác thực tế thành công.
// ======================================================================

function applyAdminCors(req, res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

/**
 * Kiểm tra Firebase App Check có điều kiện:
 * - Khi `process.env.ENFORCE_APP_CHECK === "true"` (môi trường Production), bắt buộc có
 *   X-Firebase-AppCheck token hợp lệ.
 * - Khi ở môi trường phát triển (mặc định), nếu có gửi header thì kiểm tra và ghi cảnh báo
 *   nhưng không làm gián đoạn luồng dev/emulator.
 */
async function verifyOptionalAppCheck(req) {
  const enforce = process.env.ENFORCE_APP_CHECK === "true";
  const appCheckToken = req.headers["x-firebase-appcheck"] || "";

  if (!appCheckToken) {
    if (enforce) {
      const err = new Error("Thiếu Firebase App Check token xác thực thiết bị.");
      err.statusCode = 401;
      throw err;
    }
    return;
  }

  try {
    await admin.appCheck().verifyToken(appCheckToken);
  } catch (e) {
    if (enforce) {
      const err = new Error("Firebase App Check token không hợp lệ.");
      err.statusCode = 401;
      throw err;
    }
    functions.logger.warn("App Check token không hợp lệ trong môi trường dev:", e.message);
  }
}

async function verifyAdminCaller(req) {
  return verifyAdminCallerWithDeps({
    req,
    db,
    auth: admin.auth(),
    verifyAppCheckFn: verifyOptionalAppCheck,
    logger: functions.logger,
  });
}

const adminHandlers = createAdminEndpointHandlers({
  db,
  auth: admin.auth(),
  verifyAppCheckFn: verifyOptionalAppCheck,
  logger: functions.logger,
  geminiApiKeyGetter: async () => {
    try {
      const secretVal = geminiApiKeySecret.value();
      if (secretVal && String(secretVal).trim()) {
        return String(secretVal).trim();
      }
    } catch (_) {
      // Môi trường local/test không gắn Secret Manager có thể fallback về biến môi trường
    }
    return process.env.GEMINI_API_KEY || "";
  },
});

/**
 * 4. Endpoint Khóa / Mở khóa tài khoản người dùng (Firebase Auth + Firestore + Audit Log)
 * POST /adminSetUserStatus
 * Body: { targetUid: string, status: 'active' | 'locked', reason?: string }
 */
exports.adminSetUserStatus = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyAdminCaller(req);
    const { targetUid, status, reason } = req.body || {};

    if (!targetUid || (status !== "active" && status !== "locked")) {
      res.status(400).json({ error: "Tham số targetUid hoặc status không hợp lệ." });
      return;
    }

    if (targetUid === caller.uid) {
      res.status(400).json({ error: "Quản trị viên không thể tự khóa tài khoản của chính mình." });
      return;
    }

    const isLocked = status === "locked";
    const targetDocRef = db.collection("users").doc(targetUid);
    const targetSnap = await targetDocRef.get();
    const targetEmail = targetSnap.exists ? (targetSnap.data().email || targetUid) : targetUid;

    // 1. Vô hiệu hóa hoặc khôi phục tài khoản trên Firebase Authentication
    await admin.auth().updateUser(targetUid, { disabled: isLocked });
    if (isLocked) {
      await admin.auth().revokeRefreshTokens(targetUid);
    }

    // 2. Cập nhật trạng thái trên Firestore để đồng bộ realtime với ứng dụng User
    const nowIso = new Date().toISOString();
    await targetDocRef.set(
      {
        status: status,
        updatedAt: nowIso,
      },
      { merge: true }
    );

    // 3. Ghi nhật ký quản trị sau khi thao tác thực tế thành công
    const actionCode = isLocked ? "LOCK_USER" : "UNLOCK_USER";
    const logRef = await db.collection("admin_logs").add({
      adminId: caller.uid,
      adminEmail: caller.email,
      action: actionCode,
      targetType: "user",
      targetId: targetUid,
      targetLabel: targetEmail,
      result: "success",
      details: reason
        ? `${isLocked ? "Khóa" : "Mở khóa"} tài khoản ${targetEmail}. Lý do: ${reason}`
        : `${isLocked ? "Khóa" : "Mở khóa"} tài khoản ${targetEmail} (Đồng bộ Firebase Auth & Firestore).`,
      source: "cloud_function",
      createdAt: nowIso,
    });

    res.status(200).json({
      success: true,
      targetUid: targetUid,
      status: status,
      authDisabled: isLocked,
      logId: logRef.id,
      message: isLocked
        ? `Đã khóa tài khoản ${targetEmail} trên Firebase Auth và Firestore.`
        : `Đã mở khóa tài khoản ${targetEmail}.`,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminSetUserStatus:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể cập nhật trạng thái tài khoản.",
    });
  }
});

/**
 * 5. Endpoint Cấp / Thu hồi quyền Admin (Custom Claims + Firestore + Audit Log)
 * POST /adminSetUserRole
 * Body: { targetUid: string, role: 'user' | 'admin' }
 */
exports.adminSetUserRole = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  return adminHandlers.adminSetUserRole(req, res);
});

/**
 * 6. Endpoint lấy danh sách người dùng dành cho Admin
 * GET/POST /adminListUsers
 */
exports.adminListUsers = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;

  try {
    await verifyAdminCaller(req);
    const snap = await db.collection("users").get();
    const users = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        uid: doc.id,
        name: d.name || "",
        email: d.email || "",
        role: d.role || "user",
        status: d.status || "active",
        occupation: d.occupation || null,
        createdAt: d.createdAt || null,
      };
    });

    res.status(200).json({
      success: true,
      users: users,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminListUsers:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể lấy danh sách tài khoản.",
    });
  }
});

/**
 * 7. Endpoint lấy thống kê tổng quan thực tế cho Admin Dashboard
 * GET/POST /adminGetDashboardStats
 */
exports.adminGetDashboardStats = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;

  try {
    await verifyAdminCaller(req);
    const [usersSnap, categoriesSnap, announcementsSnap] = await Promise.all([
      db.collection("users").get(),
      db.collection("system_categories").get(),
      db.collection("system_announcements").get(),
    ]);

    let activeUsers = 0;
    let lockedUsers = 0;
    usersSnap.docs.forEach((doc) => {
      const st = doc.data().status || "active";
      if (st === "locked") lockedUsers++;
      else activeUsers++;
    });

    let activeCategories = 0;
    categoriesSnap.docs.forEach((doc) => {
      if (doc.data().isActive !== false) activeCategories++;
    });

    res.status(200).json({
      success: true,
      stats: {
        totalUsers: usersSnap.size,
        activeUsers: activeUsers,
        lockedUsers: lockedUsers,
        totalSystemCategories: categoriesSnap.size,
        activeSystemCategories: activeCategories,
        totalAnnouncements: announcementsSnap.size,
      },
    });
  } catch (error) {
    functions.logger.error("Lỗi adminGetDashboardStats:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể tải số liệu thống kê quản trị.",
    });
  }
});

// ======================================================================
// GIAI ĐOẠN 1 & 2: QUẢN TRỊ CẤU HÌNH AI, SANDBOX HASH, PUBLISH/ROLLBACK & AI FEEDBACK
// ======================================================================

const _secretMemoryCache = {};

/**
 * Quản lý khóa bí mật HMAC phía Server an toàn:
 * 1. Ưu tiên đọc từ biến môi trường / Google Cloud Secret Manager (`process.env[envVarName]`).
 * 2. Hoặc đọc từ `functions.config().security?.[configProp]`.
 * 3. Nếu chưa cấu hình trên môi trường dev, tự động sinh khóa ngẫu nhiên 256-bit
 *    (`crypto.randomBytes(32).toString("hex")`) và lưu tại collection nội bộ
 *    `_server_secrets/{secretId}` (đã khóa `allow read, write: if false` trong Firestore Rules).
 * Tuyệt đối không dùng chuỗi khóa cố định hardcode trong mã nguồn.
 */
async function getOrCreateServerSecret(secretId, envVarName, configProp) {
  const fromEnv = process.env[envVarName];
  if (fromEnv && String(fromEnv).trim().length >= 16) {
    return String(fromEnv).trim();
  }

  const fromConfig = functions.config().security?.[configProp];
  if (fromConfig && String(fromConfig).trim().length >= 16) {
    return String(fromConfig).trim();
  }

  if (_secretMemoryCache[secretId]) {
    return _secretMemoryCache[secretId];
  }

  const secretRef = db.collection("_server_secrets").doc(secretId);
  const generatedSecret = await db.runTransaction(async (tx) => {
    const snap = await tx.get(secretRef);
    if (snap.exists && snap.data().secretValue && String(snap.data().secretValue).length >= 32) {
      return String(snap.data().secretValue);
    }
    const fresh = crypto.randomBytes(32).toString("hex");
    tx.set(secretRef, {
      secretId: secretId,
      secretValue: fresh,
      createdAt: new Date().toISOString(),
    });
    return fresh;
  });

  _secretMemoryCache[secretId] = generatedSecret;
  return generatedSecret;
}

async function computeSandboxSignature(configType, canonicalHash) {
  const secret = await getOrCreateServerSecret(
    "sandbox_hmac_v1",
    "SANDBOX_HMAC_SECRET",
    "sandbox_secret"
  );
  return crypto
    .createHmac("sha256", secret)
    .update(`${configType}:${canonicalHash}`, "utf8")
    .digest("hex");
}

async function computePseudonymousReporterHash(uid) {
  const secret = await getOrCreateServerSecret(
    "feedback_pseudonym_v1",
    "FEEDBACK_HMAC_SECRET",
    "feedback_secret"
  );
  return crypto
    .createHmac("sha256", secret)
    .update(`reporter:${uid}`, "utf8")
    .digest("hex");
}

async function verifyActiveUserCaller(req) {
  await verifyOptionalAppCheck(req);
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) {
    const err = new Error("Thiếu Firebase ID Token xác thực.");
    err.statusCode = 401;
    throw err;
  }
  const idToken = authHeader.substring("Bearer ".length).trim();
  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken, true);
  } catch (e) {
    const err = new Error("Phiên đăng nhập không hợp lệ hoặc đã hết hạn.");
    err.statusCode = 401;
    throw err;
  }
  const userDoc = await db.collection("users").doc(decoded.uid).get();
  if (userDoc.exists && userDoc.data().status === "locked") {
    const err = new Error("Tài khoản đã bị khóa.");
    err.statusCode = 403;
    throw err;
  }
  return {
    uid: decoded.uid,
    email: decoded.email || "",
  };
}

/**
 * 8. Endpoint Xác minh Bản nháp trên AI Sandbox (Đóng dấu chữ ký HMAC tại Backend)
 * POST /adminVerifyDraftInSandbox
 * Body: { configType: string, simulationSummary?: object }
 */
exports.adminVerifyDraftInSandbox = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyAdminCaller(req);
    const { configType, simulationSummary } = req.body || {};

    if (!ALLOWED_CONFIG_TYPES.includes(configType)) {
      res.status(400).json({ error: "Loại cấu hình configType không hợp lệ." });
      return;
    }

    const draftRef = db.collection("draft_configs").doc(configType);
    const draftSnap = await draftRef.get();
    if (!draftSnap.exists || !draftSnap.data().draftPayload) {
      res.status(404).json({ error: "Không tìm thấy bản nháp cần kiểm thử." });
      return;
    }

    const draftPayload = draftSnap.data().draftPayload;
    const validationErrors = validateConfigPayloadServerSide(configType, draftPayload);
    if (validationErrors.length > 0) {
      res.status(400).json({
        error: validationErrors.join(" "),
        validationErrors: validationErrors,
      });
      return;
    }

    const canonicalHash = computeCanonicalConfigHash(draftPayload);
    const signature = await computeSandboxSignature(configType, canonicalHash);
    const nowIso = new Date().toISOString();

    await db.collection("_sandbox_verifications").doc(configType).set({
      configType: configType,
      verifiedDraftHash: canonicalHash,
      verificationSignature: signature,
      simulationSummary: simulationSummary || {},
      verifiedBy: caller.uid,
      verifiedByEmail: caller.email,
      verifiedAt: nowIso,
    });

    await db.collection("admin_logs").add({
      adminId: caller.uid,
      adminEmail: caller.email,
      action: "VERIFY_SANDBOX_DRAFT",
      targetType: "config",
      targetId: configType,
      targetLabel: configType,
      result: "success",
      details: `Đã kiểm thử hợp lệ bản nháp ${configType} trên AI Sandbox (Hash: ${canonicalHash.substring(0, 12)}...).`,
      source: "cloud_function",
      createdAt: nowIso,
    });

    res.status(200).json({
      success: true,
      configType: configType,
      verifiedDraftHash: canonicalHash,
      verificationSignature: signature,
      verifiedAt: nowIso,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminVerifyDraftInSandbox:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể xác minh bản nháp Sandbox.",
    });
  }
});

/**
 * 9. Endpoint Xuất bản Cấu hình Nguyên tử (Atomic Publish + Snapshot + Audit Log)
 * POST /adminPublishConfig
 * Body: { configType: string, changeNote: string }
 */
exports.adminPublishConfig = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyAdminCaller(req);
    const { configType, changeNote } = req.body || {};

    if (!ALLOWED_CONFIG_TYPES.includes(configType)) {
      res.status(400).json({ error: "Loại cấu hình configType không hợp lệ." });
      return;
    }

    const cleanNote = String(changeNote || "Xuất bản cấu hình mới").trim().substring(0, 300);
    const nowIso = new Date().toISOString();
    await getOrCreateServerSecret("sandbox_hmac_v1", "SANDBOX_HMAC_SECRET", "sandbox_secret");

    const result = await db.runTransaction(async (tx) => {
      const draftRef = db.collection("draft_configs").doc(configType);
      const sandboxRef = db.collection("_sandbox_verifications").doc(configType);
      const pubRef = db.collection("published_configs").doc(configType);

      const [draftSnap, sandboxSnap, pubSnap] = await Promise.all([
        tx.get(draftRef),
        tx.get(sandboxRef),
        tx.get(pubRef),
      ]);

      if (!draftSnap.exists || !draftSnap.data().draftPayload) {
        const err = new Error("Không tìm thấy dữ liệu bản nháp để xuất bản.");
        err.statusCode = 404;
        throw err;
      }

      const draftPayload = draftSnap.data().draftPayload;
      const validationErrors = validateConfigPayloadServerSide(configType, draftPayload);
      if (validationErrors.length > 0) {
        const err = new Error(validationErrors.join(" "));
        err.statusCode = 400;
        err.validationErrors = validationErrors;
        throw err;
      }

      const currentCanonicalHash = computeCanonicalConfigHash(draftPayload);
      const expectedSignature = await computeSandboxSignature(configType, currentCanonicalHash);

      if (
        !sandboxSnap.exists ||
        sandboxSnap.data().verifiedDraftHash !== currentCanonicalHash ||
        sandboxSnap.data().verificationSignature !== expectedSignature
      ) {
        const err = new Error(
          "Bản nháp đã thay đổi hoặc chưa được kiểm thử trên AI Sandbox. Vui lòng chạy kiểm thử Sandbox trước khi xuất bản."
        );
        err.statusCode = 400;
        throw err;
      }

      const currentVersion = pubSnap.exists ? Number(pubSnap.data().version || 0) : 0;
      const nextVersion = currentVersion + 1;
      const versionDocId = `${configType}_v${nextVersion}`;
      const versionRef = db.collection("config_versions").doc(versionDocId);
      const logRef = db.collection("admin_logs").doc();

      tx.set(pubRef, {
        configType: configType,
        version: nextVersion,
        payload: draftPayload,
        payloadHash: currentCanonicalHash,
        changeNote: cleanNote,
        updatedAt: nowIso,
        updatedBy: caller.uid,
        updatedByEmail: caller.email,
      });

      tx.set(versionRef, {
        versionId: versionDocId,
        configType: configType,
        versionNumber: nextVersion,
        payloadSnapshot: draftPayload,
        payloadHash: currentCanonicalHash,
        changeNote: cleanNote,
        publishedBy: caller.uid,
        publishedByEmail: caller.email,
        publishedAt: nowIso,
      });

      tx.set(logRef, {
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "PUBLISH_CONFIG",
        targetType: "config",
        targetId: configType,
        targetLabel: `${configType} v${nextVersion}`,
        result: "success",
        details: `Xuất bản ${configType} phiên bản v${nextVersion}. Ghi chú: ${cleanNote}`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      return {
        version: nextVersion,
        versionId: versionDocId,
        payloadHash: currentCanonicalHash,
      };
    });

    res.status(200).json({
      success: true,
      configType: configType,
      version: result.version,
      versionId: result.versionId,
      payloadHash: result.payloadHash,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminPublishConfig:", error);
    const code = error.statusCode || 500;
    const body = {
      error: error.message || "Không thể xuất bản cấu hình.",
    };
    if (Array.isArray(error.validationErrors) && error.validationErrors.length > 0) {
      body.validationErrors = error.validationErrors;
    }
    res.status(code).json(body);
  }
});

/**
 * 10. Endpoint Khôi phục Phiên bản Cấu hình (Tạo version mới từ snapshot cũ, không ghi đè lịch sử)
 * POST /adminRollbackConfig
 * Body: { configType: string, targetVersionNumber: number, reason?: string }
 */
exports.adminRollbackConfig = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyAdminCaller(req);
    const { configType, targetVersionNumber, reason } = req.body || {};
    const targetVer = Number(targetVersionNumber);

    if (!ALLOWED_CONFIG_TYPES.includes(configType) || !Number.isInteger(targetVer) || targetVer < 1) {
      res.status(400).json({ error: "Tham số configType hoặc targetVersionNumber không hợp lệ." });
      return;
    }

    const nowIso = new Date().toISOString();
    const targetVersionId = `${configType}_v${targetVer}`;
    await getOrCreateServerSecret("sandbox_hmac_v1", "SANDBOX_HMAC_SECRET", "sandbox_secret");

    const result = await db.runTransaction(async (tx) => {
      const targetVerRef = db.collection("config_versions").doc(targetVersionId);
      const pubRef = db.collection("published_configs").doc(configType);
      const draftRef = db.collection("draft_configs").doc(configType);
      const sandboxRef = db.collection("_sandbox_verifications").doc(configType);

      const [targetVerSnap, pubSnap] = await Promise.all([
        tx.get(targetVerRef),
        tx.get(pubRef),
      ]);

      if (!targetVerSnap.exists || !targetVerSnap.data().payloadSnapshot) {
        const err = new Error(`Không tìm thấy bản lưu phiên bản v${targetVer} của ${configType}.`);
        err.statusCode = 404;
        throw err;
      }

      const restoredPayload = targetVerSnap.data().payloadSnapshot;
      const restoredHash = computeCanonicalConfigHash(restoredPayload);
      const signature = await computeSandboxSignature(configType, restoredHash);

      const currentVersion = pubSnap.exists ? Number(pubSnap.data().version || 0) : 0;
      const nextVersion = currentVersion + 1;
      const newVersionId = `${configType}_v${nextVersion}`;
      const newVerRef = db.collection("config_versions").doc(newVersionId);
      const logRef = db.collection("admin_logs").doc();

      const noteText = reason
        ? `Khôi phục từ v${targetVer}: ${String(reason).trim()}`
        : `Khôi phục (Rollback) về cấu hình của phiên bản v${targetVer}`;

      tx.set(pubRef, {
        configType: configType,
        version: nextVersion,
        payload: restoredPayload,
        payloadHash: restoredHash,
        rollbackFromVersion: targetVer,
        changeNote: noteText,
        updatedAt: nowIso,
        updatedBy: caller.uid,
        updatedByEmail: caller.email,
      });

      tx.set(draftRef, {
        configType: configType,
        draftPayload: restoredPayload,
        draftHash: restoredHash,
        changeNote: noteText,
        updatedAt: nowIso,
        updatedBy: caller.uid,
      });

      tx.set(sandboxRef, {
        configType: configType,
        verifiedDraftHash: restoredHash,
        verificationSignature: signature,
        verifiedBy: caller.uid,
        verifiedByEmail: caller.email,
        verifiedAt: nowIso,
      });

      tx.set(newVerRef, {
        versionId: newVersionId,
        configType: configType,
        versionNumber: nextVersion,
        payloadSnapshot: restoredPayload,
        payloadHash: restoredHash,
        rollbackFromVersion: targetVer,
        changeNote: noteText,
        publishedBy: caller.uid,
        publishedByEmail: caller.email,
        publishedAt: nowIso,
      });

      tx.set(logRef, {
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "ROLLBACK_CONFIG",
        targetType: "config",
        targetId: configType,
        targetLabel: `${configType} v${nextVersion} (từ v${targetVer})`,
        result: "success",
        details: noteText,
        source: "cloud_function",
        createdAt: nowIso,
      });

      return {
        version: nextVersion,
        versionId: newVersionId,
        rollbackFromVersion: targetVer,
      };
    });

    res.status(200).json({
      success: true,
      configType: configType,
      version: result.version,
      versionId: result.versionId,
      rollbackFromVersion: result.rollbackFromVersion,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminRollbackConfig:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể khôi phục phiên bản cấu hình.",
    });
  }
});

/**
 * 11. Endpoint Tiếp nhận Phản hồi Chất lượng AI từ Người dùng (Ẩn danh / Giả danh bảo mật)
 * POST /submitAiFeedback
 */
exports.submitAiFeedback = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyActiveUserCaller(req);
    const body = req.body || {};

    const allowedFeatures = ["ai_chat", "monthly_plan", "ocr_suggestion", "anomaly_alert"];
    const targetFeature = allowedFeatures.includes(body.targetFeature)
      ? body.targetFeature
      : "ai_chat";
    const rating = body.rating === "negative" ? "negative" : "positive";
    const feedbackMode = body.feedbackMode === "pseudonymous" ? "pseudonymous" : "anonymous";
    const reasonCode = String(body.reasonCode || "general").trim().substring(0, 60);

    let cleanNote = null;
    if (typeof body.userNote === "string" && body.userNote.trim().length > 0) {
      cleanNote = body.userNote
        .trim()
        .replace(/\d[\d.,\s]{5,}\d/g, "[SỐ_ẨN_DANH]")
        .substring(0, 250);
    }

    let cleanKeyword = null;
    if (
      typeof body.suggestedKeywordOrMerchant === "string" &&
      body.suggestedKeywordOrMerchant.trim().length > 0
    ) {
      cleanKeyword = body.suggestedKeywordOrMerchant.trim().substring(0, 80);
    }

    const reportRef = db.collection("ai_feedback_reports").doc();
    const reportId = reportRef.id;
    const nowIso = new Date().toISOString();

    const reportDoc = {
      reportId: reportId,
      targetFeature: targetFeature,
      rating: rating,
      reasonCode: reasonCode,
      aiConfigVersion: Number(body.aiConfigVersion || 1),
      heuristicsVersion: Number(body.heuristicsVersion || 1),
      modelUsed: String(body.modelUsed || "gemini-3.5-flash").substring(0, 60),
      dataTier: String(body.dataTier || "unknown").substring(0, 40),
      feedbackMode: feedbackMode,
      status: "open",
      createdAt: nowIso,
    };

    if (cleanNote) reportDoc.userNote = cleanNote;
    if (cleanKeyword) reportDoc.suggestedKeywordOrMerchant = cleanKeyword;

    const batch = db.batch();
    if (feedbackMode === "pseudonymous") {
      reportDoc.reporterHash = await computePseudonymousReporterHash(caller.uid);
      const linkRef = db.collection("_feedback_notification_links").doc(reportId);
      batch.set(linkRef, {
        reportId: reportId,
        uid: caller.uid,
        targetFeature: targetFeature,
        createdAt: nowIso,
      });
    }

    batch.set(reportRef, reportDoc);
    await batch.commit();

    res.status(200).json({
      success: true,
      reportId: reportId,
      feedbackMode: feedbackMode,
    });
  } catch (error) {
    functions.logger.error("Lỗi submitAiFeedback:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể gửi phản hồi chất lượng AI.",
    });
  }
});

/**
 * 12. Endpoint Admin Xử lý Phiếu Phản hồi AI & Gửi thông báo ẩn danh (nếu User đăng ký)
 * POST /adminResolveAiFeedback
 * Body: { reportId: string, status: 'resolved' | 'ignored', adminResolutionNote?: string, appliedAction?: string }
 */
exports.adminResolveAiFeedback = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  try {
    const caller = await verifyAdminCaller(req);
    const { reportId, status, adminResolutionNote, appliedAction } = req.body || {};

    if (!reportId || (status !== "resolved" && status !== "ignored")) {
      res.status(400).json({ error: "Tham số reportId hoặc status không hợp lệ." });
      return;
    }

    const nowIso = new Date().toISOString();
    const reportRef = db.collection("ai_feedback_reports").doc(reportId);
    const linkRef = db.collection("_feedback_notification_links").doc(reportId);

    await db.runTransaction(async (tx) => {
      const [reportSnap, linkSnap] = await Promise.all([
        tx.get(reportRef),
        tx.get(linkRef),
      ]);

      if (!reportSnap.exists) {
        const err = new Error("Không tìm thấy phiếu phản hồi AI.");
        err.statusCode = 404;
        throw err;
      }

      tx.update(reportRef, {
        status: status,
        adminResolutionNote: String(adminResolutionNote || "").trim().substring(0, 300),
        appliedAction: String(appliedAction || "reviewed").trim().substring(0, 80),
        resolvedBy: caller.uid,
        resolvedAt: nowIso,
      });

      if (status === "resolved" && linkSnap.exists && linkSnap.data().uid) {
        const notifRef = db.collection("notifications").doc();
        tx.set(notifRef, {
          notificationId: notifRef.id,
          userId: linkSnap.data().uid,
          title: "Đóng góp cải thiện AI đã được áp dụng",
          body: "Cảm ơn bạn! Phản hồi chất lượng AI của bạn đã được Quản trị viên xem xét và cập nhật vào hệ thống.",
          type: "system",
          isRead: false,
          createdAt: nowIso,
        });
        tx.delete(linkRef);
      }

      const logRef = db.collection("admin_logs").doc();
      tx.set(logRef, {
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "RESOLVE_AI_FEEDBACK",
        targetType: "ai_feedback",
        targetId: reportId,
        targetLabel: reportId,
        result: "success",
        details: `Xử lý phản hồi AI (${status}): ${String(adminResolutionNote || "").trim()}`,
        source: "cloud_function",
        createdAt: nowIso,
      });
    });

    res.status(200).json({
      success: true,
      reportId: reportId,
      status: status,
    });
  } catch (error) {
    functions.logger.error("Lỗi adminResolveAiFeedback:", error);
    const code = error.statusCode || 500;
    res.status(code).json({
      error: error.message || "Không thể cập nhật trạng thái phản hồi AI.",
    });
  }
});

// ======================================================================
// GIAI ĐOẠN 3 (BẢN VÁ NỀN): SESSION VERIFY, KNOWLEDGE PUBLISH, LIVE GEMINI SANDBOX & ADMIN CRUD
// ======================================================================

/**
 * 13. Endpoint Xác minh phiên Quản trị viên chuẩn phía Server & đồng bộ Custom Claims
 * GET/POST /adminVerifySession
 */
exports.adminVerifySession = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  return adminHandlers.adminVerifySession(req, res);
});

/**
 * 14. Endpoint Xuất bản / Tạm ngưng bài viết Tri thức Tài chính nguyên tử
 * POST /adminPublishKnowledgeBase
 * Body: { articleId: string, action?: 'publish' | 'toggle_active', isActive?: boolean, changeNote?: string }
 */
exports.adminPublishKnowledgeBase = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  return adminHandlers.adminPublishKnowledgeBase(req, res);
});

/**
 * 15. Endpoint Chạy thử nghiệm Gemini AI Sandbox (Đọc GEMINI_API_KEY từ Secret Manager, không lộ key cho Web)
 * POST /adminRunSandbox
 */
exports.adminRunSandbox = functions
  .runWith({
    secrets: [geminiApiKeySecret],
    timeoutSeconds: 30,
  })
  .https.onRequest(async (req, res) => {
    if (applyAdminCors(req, res)) return;
    return adminHandlers.adminRunSandbox(req, res);
  });

/**
 * 16. Endpoint Quản trị Danh mục Hệ thống (`system_categories`) + Audit Log Server
 * POST /adminManageSystemCategory
 */
exports.adminManageSystemCategory = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  return adminHandlers.adminManageSystemCategory(req, res);
});

/**
 * 17. Endpoint Quản trị Thông báo Hệ thống (`system_announcements`) + Audit Log Server
 * POST /adminManageAnnouncement
 */
exports.adminManageAnnouncement = functions.https.onRequest(async (req, res) => {
  if (applyAdminCors(req, res)) return;
  return adminHandlers.adminManageAnnouncement(req, res);
});


