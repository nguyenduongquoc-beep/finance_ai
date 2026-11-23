const test = require("node:test");
const assert = require("node:assert/strict");
const {
  parseAllowedAdminOrigins,
  isAllowedAdminOrigin,
  applyAdminCorsPolicy,
  verifyAdminCallerWithDeps,
  assertNotLastActiveAdmin,
  createAdminEndpointHandlers,
  cleanupUserData,
  handleAuthUserDeleteTrigger,
  USER_OWNED_COLLECTIONS,
} = require("../admin_helpers");

/**
 * In-memory Firestore mock hỗ trợ collection/doc/subcollection/limit/get/set/update/add/delete/batch/runTransaction
 * phục vụ kiểm thử đơn vị độc lập các Cloud Functions trong `admin_helpers.js`.
 */
class FakeFirestore {
  constructor(initialData = {}) {
    this.collections = new Map();
    this._autoId = 1;
    this.batchCommitSizes = [];
    for (const [colName, docs] of Object.entries(initialData)) {
      const colMap = new Map();
      for (const [docId, docData] of Object.entries(docs)) {
        colMap.set(docId, structuredClone(docData));
      }
      this.collections.set(colName, colMap);
    }
  }

  _getCol(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new Map());
    }
    return this.collections.get(name);
  }

  collection(name) {
    const store = this;
    const makeQuery = (filters = [], limitNum = null) => ({
      where(field, op, val) {
        return makeQuery([...filters, { field, op, val }], limitNum);
      },
      limit(nextLimit) {
        return makeQuery(filters, nextLimit);
      },
      async get() {
        const col = store._getCol(name);
        const matchingDocs = [];
        for (const [docId, data] of col.entries()) {
          const matchesAll = filters.every((f) => {
            if (f.op === "==") return data[f.field] === f.val;
            return false;
          });
          if (matchesAll) {
            matchingDocs.push({
              id: docId,
              ref: store.collection(name).doc(docId),
              data: () => structuredClone(data),
            });
            if (limitNum !== null && matchingDocs.length >= limitNum) break;
          }
        }
        return {
          empty: matchingDocs.length === 0,
          size: matchingDocs.length,
          docs: matchingDocs,
        };
      },
    });

    return {
      doc(id) {
        const docId = id || `auto_${store._autoId++}`;
        const docPath = `${name}/${docId}`;
        return {
          id: docId,
          _colName: name,
          collection(subName) {
            return store.collection(`${docPath}/${subName}`);
          },
          async get() {
            const col = store._getCol(name);
            const data = col.get(docId);
            return {
              id: docId,
              exists: data !== undefined,
              data: () => (data !== undefined ? structuredClone(data) : undefined),
            };
          },
          async set(payload, options = {}) {
            const col = store._getCol(name);
            if (options.merge && col.has(docId)) {
              col.set(docId, { ...col.get(docId), ...structuredClone(payload) });
            } else {
              col.set(docId, structuredClone(payload));
            }
          },
          async update(updates) {
            const col = store._getCol(name);
            if (!col.has(docId)) {
              throw new Error(`Document ${name}/${docId} does not exist`);
            }
            col.set(docId, { ...col.get(docId), ...structuredClone(updates) });
          },
          async delete() {
            store._getCol(name).delete(docId);
          },
        };
      },
      get() {
        return makeQuery().get();
      },
      limit(limitNum) {
        return makeQuery([], limitNum);
      },
      where(field, op, val) {
        return makeQuery([{ field, op, val }]);
      },
      async add(payload) {
        const docId = `auto_${store._autoId++}`;
        store._getCol(name).set(docId, structuredClone(payload));
        return { id: docId };
      },
    };
  }

  async recursiveDelete(docRef) {
    if (!docRef) return;
    const prefix = `${docRef._colName}/${docRef.id}/`;
    for (const [colName, colMap] of this.collections.entries()) {
      if (colName.startsWith(prefix)) {
        colMap.clear();
      }
    }
    if (typeof docRef.delete === "function") {
      await docRef.delete();
    }
  }

  batch() {
    const store = this;
    const ops = [];
    return {
      delete(ref) {
        ops.push(async () => {
          if (ref && typeof ref.delete === "function") {
            await ref.delete();
          }
        });
      },
      async commit() {
        store.batchCommitSizes.push(ops.length);
        for (const op of ops) {
          await op();
        }
      },
    };
  }

  async runTransaction(callback) {
    const tx = {
      get: (docRef) => docRef.get(),
      set: (docRef, payload, options) => docRef.set(payload, options),
      update: (docRef, updates) => docRef.update(updates),
      delete: (docRef) => docRef.delete(),
    };
    return callback(tx);
  }
}

function createFakeAuth({ verifiedTokens = {}, users = {} } = {}) {
  const userRecords = new Map(Object.entries(structuredClone(users)));
  const revokedUids = [];
  return {
    async verifyIdToken(token) {
      if (!verifiedTokens[token]) {
        throw new Error("Invalid ID token");
      }
      return structuredClone(verifiedTokens[token]);
    },
    async getUser(uid) {
      if (!userRecords.has(uid)) {
        const err = new Error(`User not found: ${uid}`);
        err.code = "auth/user-not-found";
        throw err;
      }
      return structuredClone(userRecords.get(uid));
    },
    async updateUser(uid, updates) {
      if (!userRecords.has(uid)) {
        const err = new Error(`User not found: ${uid}`);
        err.code = "auth/user-not-found";
        throw err;
      }
      const prev = userRecords.get(uid);
      userRecords.set(uid, { ...prev, ...structuredClone(updates) });
      return structuredClone(userRecords.get(uid));
    },
    async setCustomUserClaims(uid, claims) {
      const prev = userRecords.get(uid) || { uid };
      userRecords.set(uid, { ...prev, customClaims: structuredClone(claims) });
    },
    async revokeRefreshTokens(uid) {
      revokedUids.push(uid);
    },
    async deleteUser(uid) {
      if (!userRecords.has(uid)) {
        const err = new Error(`User not found: ${uid}`);
        err.code = "auth/user-not-found";
        throw err;
      }
      userRecords.delete(uid);
    },
    _getStoredUser(uid) {
      return userRecords.get(uid);
    },
    _getRevokedUids() {
      return [...revokedUids];
    },
  };
}

function createMockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    set(name, value) {
      this.headers[String(name).toLowerCase()] = value;
      return this;
    },
    getHeader(name) {
      return this.headers[String(name).toLowerCase()];
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    send(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

test("adminVerifySession: từ chối 401/403 và tự đồng bộ admin claim nhưng vẫn bảo toàn claims cũ", async () => {
  const db = new FakeFirestore({
    users: {
      admin_no_claim: { email: "admin@test.com", name: "Admin", role: "admin", status: "active" },
      normal_user: { email: "user@test.com", name: "User", role: "user", status: "active" },
      locked_admin: { email: "locked@test.com", name: "Locked", role: "admin", status: "locked" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: {
      tok_admin_no_claim: { uid: "admin_no_claim", email: "admin@test.com" },
      tok_user: { uid: "normal_user", email: "user@test.com" },
      tok_locked: { uid: "locked_admin", email: "locked@test.com", admin: true },
    },
    users: {
      admin_no_claim: { uid: "admin_no_claim", customClaims: { plan: "pro", cohort: "vn" } },
      normal_user: { uid: "normal_user", customClaims: { plan: "free" } },
    },
  });

  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  // 1. Không gửi token -> 401
  const resNoTok = createMockRes();
  await handlers.adminVerifySession({ method: "GET", headers: {} }, resNoTok);
  assert.equal(resNoTok.statusCode, 401);

  // 2. Tài khoản thường -> 403
  const resUser = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { authorization: "Bearer tok_user" } },
    resUser
  );
  assert.equal(resUser.statusCode, 403);

  // 3. Admin bị khóa -> 403
  const resLocked = createMockRes();
  await handlers.adminVerifySession(
    { method: "POST", headers: { authorization: "Bearer tok_locked" } },
    resLocked
  );
  assert.equal(resLocked.statusCode, 403);

  // 4. Admin Firestore chưa có claim -> đồng bộ admin=true VÀ giữ nguyên { plan: 'pro', cohort: 'vn' }
  const resAdmin = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { authorization: "Bearer tok_admin_no_claim" } },
    resAdmin
  );
  assert.equal(resAdmin.statusCode, 200);
  assert.equal(resAdmin.body.verifiedByServer, true);
  assert.equal(resAdmin.body.claimsSynced, true);
  assert.deepEqual(auth._getStoredUser("admin_no_claim").customClaims, {
    plan: "pro",
    cohort: "vn",
    admin: true,
  });

  // 5. adminSetUserRole cũng phải giữ nguyên claims sẵn có trên targetUid
  const resRole = createMockRes();
  await handlers.adminSetUserRole(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_admin_no_claim" },
      body: { targetUid: "normal_user", role: "admin" },
    },
    resRole
  );
  assert.equal(resRole.statusCode, 200);
  assert.deepEqual(auth._getStoredUser("normal_user").customClaims, {
    plan: "free",
    admin: true,
  });
});

test("adminManageSystemCategory & adminManageAnnouncement: ghi CRUD + admin_logs từ Server", async () => {
  const db = new FakeFirestore({
    users: {
      admin1: { email: "admin@app.vn", role: "admin", status: "active" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: { tok_a: { uid: "admin1", email: "admin@app.vn", admin: true } },
  });
  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  const resCat = createMockRes();
  await handlers.adminManageSystemCategory(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: {
        action: "save",
        isNew: true,
        template: { id: "cat_1", name: "Cà phê", type: "expense", icon: "coffee", color: 0xff00aa },
      },
    },
    resCat
  );
  assert.equal(resCat.statusCode, 200);
  assert.equal(resCat.body.categoryId, "cat_1");

  const resAnn = createMockRes();
  await handlers.adminManageAnnouncement(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: {
        action: "save",
        isNew: true,
        announcement: {
          id: "ann_1",
          title: "Bảo trì hệ thống",
          message: "Bảo trì 22h",
          level: "maintenance",
          isActive: true,
        },
      },
    },
    resAnn
  );
  assert.equal(resAnn.statusCode, 200);

  const logs = Array.from(db._getCol("admin_logs").values());
  assert.equal(logs.length, 2);
  assert.equal(logs[0].action, "CREATE_SYSTEM_CATEGORY");
  assert.equal(logs[1].action, "CREATE_ANNOUNCEMENT");
});

test("Giai đoạn 4A CORS: siết allowlist ADMIN_ALLOWED_ORIGINS, localhost dev, chặn origin lạ và đúng preflight OPTIONS", async () => {
  const parsed = parseAllowedAdminOrigins("https://admin.finance-ai.test/, *, invalid-url, https://staging-web.example.com");
  assert.deepEqual(parsed, ["https://admin.finance-ai.test", "https://staging-web.example.com"]);

  // 1. Origin hợp lệ trong ADMIN_ALLOWED_ORIGINS được cấp đúng ACAO (không dùng `*`) và đi tiếp
  const resValid = createMockRes();
  const blockedValid = applyAdminCorsPolicy(
    {
      method: "POST",
      headers: { origin: "https://admin.finance-ai.test" },
    },
    resValid,
    { allowedOriginsEnv: "https://admin.finance-ai.test", allowLocalhost: false }
  );
  assert.equal(blockedValid, false);
  assert.equal(resValid.getHeader("access-control-allow-origin"), "https://admin.finance-ai.test");
  assert.equal(resValid.getHeader("vary"), "Origin");
  assert.ok(resValid.getHeader("access-control-allow-headers").includes("Authorization"));
  assert.ok(resValid.getHeader("access-control-allow-headers").includes("X-Firebase-AppCheck"));

  // 2. Preflight OPTIONS từ origin hợp lệ (hoặc localhost dev) trả 204 với đủ header Authorization & X-Firebase-AppCheck
  const resPreflight = createMockRes();
  const endedPreflight = applyAdminCorsPolicy(
    {
      method: "OPTIONS",
      headers: { origin: "http://localhost:5173" },
    },
    resPreflight,
    { allowedOriginsEnv: "", allowLocalhost: true }
  );
  assert.equal(endedPreflight, true);
  assert.equal(resPreflight.statusCode, 204);
  assert.equal(resPreflight.getHeader("access-control-allow-origin"), "http://localhost:5173");
  assert.equal(resPreflight.getHeader("access-control-allow-methods"), "GET, POST, OPTIONS");
  assert.equal(
    resPreflight.getHeader("access-control-allow-headers"),
    "Content-Type, Authorization, X-Firebase-AppCheck"
  );

  // 3. Origin lạ trên cả OPTIONS lẫn POST bị từ chối 403 và KHÔNG được cấp Access-Control-Allow-Origin
  for (const method of ["OPTIONS", "POST"]) {
    const resEvil = createMockRes();
    const endedEvil = applyAdminCorsPolicy(
      {
        method,
        headers: { origin: "https://evil.attacker.example" },
      },
      resEvil,
      { allowedOriginsEnv: "https://admin.finance-ai.test", allowLocalhost: true }
    );
    assert.equal(endedEvil, true);
    assert.equal(resEvil.statusCode, 403);
    assert.equal(resEvil.getHeader("access-control-allow-origin"), undefined);
    assert.equal(resEvil.getHeader("vary"), "Origin");
  }

  // Khi tắt localhost dev mode thì localhost cũng bị từ chối
  const resLocalOff = createMockRes();
  const endedLocalOff = applyAdminCorsPolicy(
    { method: "GET", headers: { origin: "http://127.0.0.1:8080" } },
    resLocalOff,
    { allowedOriginsEnv: "https://admin.finance-ai.test", allowLocalhost: false }
  );
  assert.equal(endedLocalOff, true);
  assert.equal(resLocalOff.statusCode, 403);
  assert.equal(resLocalOff.getHeader("access-control-allow-origin"), undefined);

  // 4. Request không gửi Origin (CLI / native) đi qua CORS nhưng KHÔNG cấp `*`, và vẫn bị verifyAdminCaller chặn nếu thiếu Token
  const resNoOrigin = createMockRes();
  const endedNoOrigin = applyAdminCorsPolicy(
    { method: "POST", headers: {} },
    resNoOrigin,
    { allowedOriginsEnv: "https://admin.finance-ai.test", allowLocalhost: false }
  );
  assert.equal(endedNoOrigin, false);
  assert.equal(resNoOrigin.getHeader("access-control-allow-origin"), undefined);

  // 5. Không coi CORS là cơ chế thay thế xác thực Token + X-Firebase-AppCheck
  const db = new FakeFirestore({
    users: { admin1: { email: "admin@app.vn", role: "admin", status: "active" } },
  });
  const auth = createFakeAuth({
    verifiedTokens: { tok_admin: { uid: "admin1", email: "admin@app.vn", admin: true } },
  });
  const checkedAppCheck = [];
  const handlers = createAdminEndpointHandlers({
    db,
    auth,
    verifyAppCheckFn: async (r) => {
      checkedAppCheck.push(r.headers["x-firebase-appcheck"] || "");
    },
    logger: { error() {}, warn() {} },
  });

  // Origin hợp lệ nhưng thiếu Bearer token -> vẫn 401
  const resUnauth = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { origin: "http://localhost:5000" } },
    resUnauth
  );
  assert.equal(resUnauth.statusCode, 401);

  // Origin hợp lệ + Bearer token + X-Firebase-AppCheck -> 200
  const resAuth = createMockRes();
  await handlers.adminVerifySession(
    {
      method: "GET",
      headers: {
        origin: "http://localhost:5000",
        authorization: "Bearer tok_admin",
        "x-firebase-appcheck": "appcheck_tok_123",
      },
    },
    resAuth
  );
  assert.equal(resAuth.statusCode, 200);
  assert.equal(resAuth.body.verifiedByServer, true);
  assert.equal(checkedAppCheck.includes("appcheck_tok_123"), true);
});

test("Giai đoạn 4A verifyAdminCallerWithDeps: từ chối 403 nếu tài khoản có claim admin nhưng users/{uid} bị xóa hoặc không active", async () => {
  const db = new FakeFirestore({
    users: {
      admin_no_status: { email: "nostatus@app.vn", role: "admin" },
      admin_active: { email: "ok@app.vn", role: "admin", status: "active" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: {
      tok_deleted: { uid: "admin_deleted", email: "deleted@app.vn", admin: true },
      tok_no_status: { uid: "admin_no_status", email: "nostatus@app.vn", admin: true },
      tok_ok: { uid: "admin_active", email: "ok@app.vn", admin: true },
    },
  });
  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  const resDeleted = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { authorization: "Bearer tok_deleted" } },
    resDeleted
  );
  assert.equal(resDeleted.statusCode, 403);

  const resNoStatus = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { authorization: "Bearer tok_no_status" } },
    resNoStatus
  );
  assert.equal(resNoStatus.statusCode, 403);

  const resOk = createMockRes();
  await handlers.adminVerifySession(
    { method: "GET", headers: { authorization: "Bearer tok_ok" } },
    resOk
  );
  assert.equal(resOk.statusCode, 200);
});

test("cleanupUserData: dọn sạch mọi collection (gồm >500 docs chia batch, chat_sessions, support_tickets + messages, subcollections, OTP) và bảo toàn user khác", async () => {
  const txInit = {
    tx_other: { userId: "user_other", amount: 30000 },
  };
  // Tạo 650 giao dịch cho user_target để kiểm chứng chia batch (<= 400 writes/batch < giới hạn 500)
  for (let i = 1; i <= 650; i += 1) {
    txInit[`tx_target_${i}`] = { userId: "user_target", amount: 10000 };
  }

  const db = new FakeFirestore({
    users: {
      user_target: { email: "target@example.com", name: "Target User", status: "active", role: "user" },
      user_other: { email: "other@example.com", name: "Other User", status: "active", role: "user" },
    },
    "users/user_target/chat_sessions": {
      cs_sub_1: { title: "Hỏi AI riêng tư" },
    },
    "users/user_target/quickTemplates": {
      qt_1: { title: "Cà phê sáng" },
    },
    "users/user_other/chat_sessions": {
      cs_other_sub: { title: "Chat user khác" },
    },
    wallets: {
      w_target: { userId: "user_target", name: "Ví Tiền Mặt", balance: 500000 },
      w_other: { userId: "user_other", name: "Ví Khác", balance: 100000 },
    },
    categories: {
      cat_target: { userId: "user_target", name: "Ăn uống" },
    },
    transactions: txInit,
    budgets: {
      b_target: { userId: "user_target", limit: 2000000 },
    },
    savingGoals: {
      sg_target: { userId: "user_target", targetAmount: 10000000 },
    },
    recurringTransactions: {
      rec_target: { userId: "user_target", amount: 5000000 },
    },
    monthly_plans: {
      mp_target: { userId: "user_target", targetMonth: "11/2026" },
    },
    chat_sessions: {
      cs_top_target: { userId: "user_target", title: "Top-level legacy chat" },
      cs_top_other: { userId: "user_other", title: "Top-level other chat" },
    },
    support_tickets: {
      tk_target: { userId: "user_target", title: "Cần hỗ trợ" },
      tk_other: { userId: "user_other", title: "Vé người khác" },
    },
    "support_tickets/tk_target/messages": {
      m1: { body: "Tin nhắn 1" },
      m2: { body: "Tin nhắn 2" },
    },
    "support_tickets/tk_other/messages": {
      m_other: { body: "Tin nhắn người khác" },
    },
    _otp_verifications: {
      "target@example.com": { otpHash: "abc", resendAvailableAt: 12345 },
      "other@example.com": { otpHash: "xyz", resendAvailableAt: 67890 },
    },
  });

  const result = await cleanupUserData({
    db,
    uid: "user_target",
    email: "target@example.com",
    deletedBy: "system",
  });

  assert.equal(result.userDocDeleted, true);
  assert.equal(result.otpCleaned, true);
  assert.equal(result.collectionsCleaned.wallets, 1);
  assert.equal(result.collectionsCleaned.transactions, 650);
  assert.equal(result.collectionsCleaned.budgets, 1);
  assert.equal(result.collectionsCleaned.savingGoals, 1);
  assert.equal(result.collectionsCleaned.chat_sessions, 1);
  assert.equal(result.collectionsCleaned.support_tickets, 1);
  assert.equal(result.supportMessagesCleaned, 2);

  // Mọi batch đều <= 400 writes (an toàn dưới trần 500 của Firestore)
  assert.ok(db.batchCommitSizes.length >= 2);
  assert.ok(db.batchCommitSizes.every((size) => size > 0 && size <= 400));

  // Kiểm tra target user + subcollections + support_tickets/messages đã bị xóa sạch
  assert.equal((await db.collection("users").doc("user_target").get()).exists, false);
  assert.equal(db._getCol("users/user_target/chat_sessions").size, 0);
  assert.equal(db._getCol("users/user_target/quickTemplates").size, 0);
  assert.equal((await db.collection("wallets").doc("w_target").get()).exists, false);
  assert.equal(db._getCol("transactions").size, 1); // Chỉ còn tx_other
  assert.equal((await db.collection("chat_sessions").doc("cs_top_target").get()).exists, false);
  assert.equal((await db.collection("support_tickets").doc("tk_target").get()).exists, false);
  assert.equal(db._getCol("support_tickets/tk_target/messages").size, 0);
  assert.equal((await db.collection("_otp_verifications").doc("target@example.com").get()).exists, false);

  // Kiểm tra dữ liệu của user_other hoàn toàn được bảo toàn
  assert.equal((await db.collection("users").doc("user_other").get()).exists, true);
  assert.equal(db._getCol("users/user_other/chat_sessions").size, 1);
  assert.equal((await db.collection("wallets").doc("w_other").get()).exists, true);
  assert.equal((await db.collection("transactions").doc("tx_other").get()).exists, true);
  assert.equal((await db.collection("chat_sessions").doc("cs_top_other").get()).exists, true);
  assert.equal((await db.collection("support_tickets").doc("tk_other").get()).exists, true);
  assert.equal(db._getCol("support_tickets/tk_other/messages").size, 1);
  assert.equal((await db.collection("_otp_verifications").doc("other@example.com").get()).exists, true);

  // Kiểm tra nhật ký kiểm toán không rò rỉ thống kê tài chính cá nhân
  const adminLogs = Array.from(db._getCol("admin_logs").values());
  const cleanupLog = adminLogs.find((l) => l.action === "CLEANUP_DELETED_AUTH_USER");
  assert.ok(cleanupLog, "Phải ghi nhật ký CLEANUP_DELETED_AUTH_USER");
  assert.equal(cleanupLog.targetId, "user_target");
  assert.equal(cleanupLog.result, "success");
  assert.equal(cleanupLog.details.includes("wallets"), false);
  assert.equal(cleanupLog.details.includes("transactions"), false);
});

test("adminDeleteUser + handleAuthUserDeleteTrigger: chống tự xóa, không chạy lặp/trùng log và giữ nguyên Zero-Knowledge Privacy", async () => {
  const db = new FakeFirestore({
    users: {
      admin_uid: { email: "admin@finance.app", role: "admin", status: "active" },
      user_uid: { email: "victim@finance.app", role: "user", status: "active" },
    },
    wallets: {
      w_victim: { userId: "user_uid", balance: 250000 },
    },
    support_tickets: {
      tk_victim: { userId: "user_uid", title: "Hỗ trợ" },
    },
    "support_tickets/tk_victim/messages": {
      msg_1: { body: "Xin chào" },
    },
  });

  const auth = createFakeAuth({
    verifiedTokens: {
      tok_admin: { uid: "admin_uid", email: "admin@finance.app", admin: true },
      tok_user: { uid: "user_uid", email: "victim@finance.app" },
    },
    users: {
      admin_uid: { uid: "admin_uid", email: "admin@finance.app", customClaims: { admin: true } },
      user_uid: { uid: "user_uid", email: "victim@finance.app" },
    },
  });

  const fixedNow = Date.UTC(2026, 10, 21, 10, 0, 0);
  const handlers = createAdminEndpointHandlers({
    db,
    auth,
    nowProvider: () => fixedNow,
    logger: { error() {}, warn() {}, info() {} },
  });

  // 1. Từ chối method khác POST
  const resGet = createMockRes();
  await handlers.adminDeleteUser({ method: "GET" }, resGet);
  assert.equal(resGet.statusCode, 405);

  // 2. Từ chối caller không có token admin
  const resNoAuth = createMockRes();
  await handlers.adminDeleteUser(
    { method: "POST", headers: { authorization: "Bearer tok_user" }, body: { targetUid: "user_uid" } },
    resNoAuth
  );
  assert.equal(resNoAuth.statusCode, 403);

  // 3. Từ chối Admin tự xóa chính mình
  const resSelf = createMockRes();
  await handlers.adminDeleteUser(
    { method: "POST", headers: { authorization: "Bearer tok_admin" }, body: { targetUid: "admin_uid" } },
    resSelf
  );
  assert.equal(resSelf.statusCode, 400);
  assert.match(resSelf.body.error, /không thể tự xóa/i);

  // 4. Xóa thành công tài khoản người dùng
  const resOk = createMockRes();
  await handlers.adminDeleteUser(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_admin" },
      body: { targetUid: "user_uid", reason: "Vi phạm điều khoản dịch vụ" },
    },
    resOk
  );
  assert.equal(resOk.statusCode, 200);
  assert.equal(resOk.body.success, true);
  assert.equal(resOk.body.authDeleted, true);
  assert.equal(resOk.body.dataCleaned, true);

  // Zero-Knowledge Privacy: response KHÔNG được trả cleanupResult hay bất kỳ số liệu tài chính nào
  assert.equal(Object.prototype.hasOwnProperty.call(resOk.body, "cleanupResult"), false);
  assert.equal(JSON.stringify(resOk.body).includes("wallets"), false);
  assert.equal(JSON.stringify(resOk.body).includes("250000"), false);

  // Kiểm tra tài khoản đã bị xóa khỏi Firebase Auth + Firestore + support_tickets/messages
  assert.equal(auth._getStoredUser("user_uid"), undefined);
  assert.equal((await db.collection("users").doc("user_uid").get()).exists, false);
  assert.equal((await db.collection("wallets").doc("w_victim").get()).exists, false);
  assert.equal((await db.collection("support_tickets").doc("tk_victim").get()).exists, false);
  assert.equal(db._getCol("support_tickets/tk_victim/messages").size, 0);

  // 5. Khi Auth onDelete trigger bắn ngay sau đó -> nhận diện marker và bỏ qua (KHÔNG ghi log trùng)
  const triggerRes = await handleAuthUserDeleteTrigger({
    db,
    user: { uid: "user_uid", email: "victim@finance.app" },
    nowProvider: () => fixedNow + 5000,
    logger: { info() {}, warn() {}, error() {} },
  });
  assert.equal(triggerRes.skipped, true);
  assert.equal(triggerRes.reason, "handled_by_adminDeleteUser");
  assert.equal((await db.collection("_user_deletion_markers").doc("user_uid").get()).exists, false);

  // Chỉ có duy nhất 1 bản ghi ADMIN_DELETE_USER trong admin_logs (không bị trùng CLEANUP_DELETED_AUTH_USER)
  const adminLogs = Array.from(db._getCol("admin_logs").values());
  assert.equal(adminLogs.length, 1);
  assert.equal(adminLogs[0].action, "ADMIN_DELETE_USER");
  assert.equal(adminLogs[0].adminId, "admin_uid");
  assert.equal(adminLogs[0].targetId, "user_uid");
  assert.match(adminLogs[0].details, /Vi phạm điều khoản dịch vụ/);
});

test("handleAuthUserDeleteTrigger: khi user bị xóa độc lập (Console / tự xóa), vẫn dọn sạch dữ liệu & ghi 1 log hệ thống", async () => {
  const db = new FakeFirestore({
    users: {
      self_del_uid: { email: "self@finance.app", role: "user", status: "active" },
    },
    wallets: {
      w1: { userId: "self_del_uid", balance: 100000 },
    },
    support_tickets: {
      tk1: { userId: "self_del_uid", title: "Câu hỏi" },
    },
    "support_tickets/tk1/messages": {
      m1: { body: "Nội dung" },
    },
  });

  const res = await handleAuthUserDeleteTrigger({
    db,
    user: { uid: "self_del_uid", email: "self@finance.app" },
    logger: { info() {}, warn() {}, error() {} },
  });
  assert.equal(Boolean(res.skipped), false);
  assert.equal(res.userDocDeleted, true);
  assert.equal((await db.collection("wallets").doc("w1").get()).exists, false);
  assert.equal((await db.collection("support_tickets").doc("tk1").get()).exists, false);
  assert.equal(db._getCol("support_tickets/tk1/messages").size, 0);

  const logs = Array.from(db._getCol("admin_logs").values());
  assert.equal(logs.length, 1);
  assert.equal(logs[0].action, "CLEANUP_DELETED_AUTH_USER");
});

test("Thu hồi quyền Admin tức thì: adminSetUserRole gọi revokeRefreshTokens khi hạ về user & verifyAdminCaller chặn ngay JWT cũ còn admin=true", async () => {
  const db = new FakeFirestore({
    users: {
      admin_a: { email: "a@app.vn", name: "Admin A", role: "admin", status: "active" },
      admin_b: { email: "b@app.vn", name: "Admin B", role: "admin", status: "active" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: {
      tok_a: { uid: "admin_a", email: "a@app.vn", admin: true },
      tok_b_stale: { uid: "admin_b", email: "b@app.vn", admin: true },
    },
    users: {
      admin_a: { uid: "admin_a", customClaims: { admin: true } },
      admin_b: { uid: "admin_b", customClaims: { admin: true, tier: "ops" } },
    },
  });
  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  // 1. Admin A hạ quyền Admin B về user -> cập nhật claims (giữ claim phụ) + Firestore + revokeRefreshTokens
  const resDemote = createMockRes();
  await handlers.adminSetUserRole(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { targetUid: "admin_b", role: "user" },
    },
    resDemote
  );
  assert.equal(resDemote.statusCode, 200);
  assert.equal(resDemote.body.tokensRevoked, true);
  assert.deepEqual(auth._getStoredUser("admin_b").customClaims, {
    tier: "ops",
    admin: false,
  });
  assert.deepEqual(auth._getRevokedUids(), ["admin_b"]);
  assert.equal((await db.collection("users").doc("admin_b").get()).data().role, "user");

  // 2. Ngay cả khi JWT cũ của Admin B vẫn còn `admin: true`, verifyAdminCaller PHẢI từ chối 403 lập tức
  const resStale = createMockRes();
  await handlers.adminVerifySession(
    {
      method: "GET",
      headers: { authorization: "Bearer tok_b_stale" },
    },
    resStale
  );
  assert.equal(resStale.statusCode, 403);
});

test("Bảo vệ Admin hoạt động cuối cùng: chặn khóa, hạ quyền và xóa khi không còn Admin active nào khác", async () => {
  // 1. Kiểm tra trực tiếp helper assertNotLastActiveAdmin
  const soloDb = new FakeFirestore({
    users: {
      only_admin: { email: "only@app.vn", role: "admin", status: "active" },
      locked_admin: { email: "locked@app.vn", role: "admin", status: "locked" },
      normal_user: { email: "u@app.vn", role: "user", status: "active" },
    },
  });
  await assert.rejects(
    () =>
      assertNotLastActiveAdmin(soloDb, "only_admin", {
        role: "admin",
        status: "active",
      }),
    (err) => err.statusCode === 400
  );
  // Tài khoản locked_admin KHÔNG phải active admin nên vẫn được phép xóa/cập nhật
  await assertNotLastActiveAdmin(soloDb, "locked_admin", {
    role: "admin",
    status: "locked",
  });

  // 2. Mô phỏng race condition đồng thời (caller vượt qua verifyCaller ngay trước khi chính caller bị hạ quyền,
  //    khiến target trở thành Admin active duy nhất còn lại) -> cả 3 endpoint đều phải chặn 400 & rollback Auth
  const makeRaceDb = () => {
    const inner = new FakeFirestore({
      users: {
        admin_caller: { email: "caller@app.vn", role: "admin", status: "active" },
        admin_target: { email: "target@app.vn", role: "admin", status: "active" },
      },
    });
    let callerReadCount = 0;
    const origCollection = inner.collection.bind(inner);
    inner.collection = (name) => {
      const col = origCollection(name);
      if (name !== "users") return col;
      const origDoc = col.doc.bind(col);
      col.doc = (id) => {
        const d = origDoc(id);
        if (id !== "admin_caller") return d;
        const origGet = d.get.bind(d);
        d.get = async () => {
          const snap = await origGet();
          callerReadCount += 1;
          if (callerReadCount === 1) {
            // Ngay sau khi caller xác thực xong, giả lập caller bị khóa đồng thời bởi phiên khác
            inner._getCol("users").set("admin_caller", {
              email: "caller@app.vn",
              role: "admin",
              status: "locked",
            });
          }
          return snap;
        };
        return d;
      };
      return col;
    };
    return inner;
  };

  // 2a. Chặn hạ quyền Admin cuối cùng
  const raceDbRole = makeRaceDb();
  const raceAuthRole = createFakeAuth({
    verifiedTokens: { tok_c: { uid: "admin_caller", email: "caller@app.vn", admin: true } },
    users: {
      admin_caller: { uid: "admin_caller", customClaims: { admin: true } },
      admin_target: { uid: "admin_target", customClaims: { admin: true } },
    },
  });
  const hRole = createAdminEndpointHandlers({
    db: raceDbRole,
    auth: raceAuthRole,
    logger: { error() {}, warn() {} },
  });
  const resRole = createMockRes();
  await hRole.adminSetUserRole(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_c" },
      body: { targetUid: "admin_target", role: "user" },
    },
    resRole
  );
  assert.equal(resRole.statusCode, 400);
  assert.equal(raceAuthRole._getStoredUser("admin_target").customClaims.admin, true);
  assert.equal((await raceDbRole.collection("users").doc("admin_target").get()).data().role, "admin");

  // 2b. Chặn khóa Admin cuối cùng
  const raceDbLock = makeRaceDb();
  const raceAuthLock = createFakeAuth({
    verifiedTokens: { tok_c: { uid: "admin_caller", email: "caller@app.vn", admin: true } },
    users: {
      admin_caller: { uid: "admin_caller", disabled: false },
      admin_target: { uid: "admin_target", disabled: false },
    },
  });
  const hLock = createAdminEndpointHandlers({
    db: raceDbLock,
    auth: raceAuthLock,
    logger: { error() {}, warn() {} },
  });
  const resLock = createMockRes();
  await hLock.adminSetUserStatus(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_c" },
      body: { targetUid: "admin_target", status: "locked" },
    },
    resLock
  );
  assert.equal(resLock.statusCode, 400);
  assert.equal(raceAuthLock._getStoredUser("admin_target").disabled, false);
  assert.equal((await raceDbLock.collection("users").doc("admin_target").get()).data().status, "active");

  // 2c. Chặn xóa Admin cuối cùng
  const raceDbDel = makeRaceDb();
  const raceAuthDel = createFakeAuth({
    verifiedTokens: { tok_c: { uid: "admin_caller", email: "caller@app.vn", admin: true } },
    users: {
      admin_caller: { uid: "admin_caller" },
      admin_target: { uid: "admin_target" },
    },
  });
  const hDel = createAdminEndpointHandlers({
    db: raceDbDel,
    auth: raceAuthDel,
    logger: { error() {}, warn() {} },
  });
  const resDel = createMockRes();
  await hDel.adminDeleteUser(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_c" },
      body: { targetUid: "admin_target" },
    },
    resDel
  );
  assert.equal(resDel.statusCode, 400);
  assert.ok(raceAuthDel._getStoredUser("admin_target"));
  assert.equal((await raceDbDel.collection("users").doc("admin_target").get()).exists, true);
});

test("adminListUsers (Zero-Knowledge) chỉ trả 7 trường phi tài chính & adminSetUserStatus xử lý mềm user-not-found + rollback Auth khi Firestore lỗi", async () => {
  const db = new FakeFirestore({
    users: {
      admin_1: { email: "admin@app.vn", name: "Admin", role: "admin", status: "active" },
      u_rich: {
        email: "rich@app.vn",
        name: "Nguyễn Văn Giàu",
        role: "user",
        status: "active",
        occupation: "Kỹ sư",
        createdAt: "2026-10-15T00:00:00.000Z",
        monthlyIncome: 85000000,
        savingGoal: "Mua căn hộ 3 tỷ",
        monthlyPlans: { "11_2026": { targetSavingAmount: 25000000 } },
      },
      u_firestore_only: {
        email: "ghost@app.vn",
        name: "Ghost User",
        role: "user",
        status: "active",
      },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: { tok_admin: { uid: "admin_1", email: "admin@app.vn", admin: true } },
    users: {
      admin_1: { uid: "admin_1", disabled: false, customClaims: { admin: true } },
      u_rich: { uid: "u_rich", disabled: false },
    },
  });
  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  // 1. Zero-Knowledge adminListUsers
  const resList = createMockRes();
  await handlers.adminListUsers(
    { method: "GET", headers: { authorization: "Bearer tok_admin" } },
    resList
  );
  assert.equal(resList.statusCode, 200);
  const richUser = resList.body.users.find((u) => u.uid === "u_rich");
  assert.deepEqual(Object.keys(richUser).sort(), [
    "createdAt",
    "email",
    "name",
    "occupation",
    "role",
    "status",
    "uid",
  ]);
  assert.equal(Object.prototype.hasOwnProperty.call(richUser, "monthlyIncome"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(richUser, "savingGoal"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(richUser, "monthlyPlans"), false);

  // 2. Xử lý mềm auth/user-not-found trên adminSetUserStatus
  const resGhost = createMockRes();
  await handlers.adminSetUserStatus(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_admin" },
      body: { targetUid: "u_firestore_only", status: "locked", reason: "Hồ sơ mồ côi" },
    },
    resGhost
  );
  assert.equal(resGhost.statusCode, 200);
  assert.equal(resGhost.body.authUpdated, false);
  assert.equal((await db.collection("users").doc("u_firestore_only").get()).data().status, "locked");

  // 3. Rollback Auth disabled khi bước ghi Firestore thất bại
  const origRunTx = db.runTransaction.bind(db);
  db.runTransaction = async () => {
    throw new Error("Simulated Firestore write failure");
  };
  const resFail = createMockRes();
  await handlers.adminSetUserStatus(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_admin" },
      body: { targetUid: "u_rich", status: "locked" },
    },
    resFail
  );
  db.runTransaction = origRunTx;
  assert.equal(resFail.statusCode, 500);
  assert.equal(auth._getStoredUser("u_rich").disabled, false);
  assert.equal((await db.collection("users").doc("u_rich").get()).data().status, "active");
});

test("adminManageAnnouncement: giữ nguyên createdBy/createdAt khi sửa (lưu thêm updatedBy) & trả 404 khi toggle/delete ID không tồn tại", async () => {
  const db = new FakeFirestore({
    users: {
      admin_a: { email: "creator@app.vn", role: "admin", status: "active" },
      admin_b: { email: "editor@app.vn", role: "admin", status: "active" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: {
      tok_a: { uid: "admin_a", email: "creator@app.vn", admin: true },
      tok_b: { uid: "admin_b", email: "editor@app.vn", admin: true },
    },
  });
  let clock = Date.UTC(2026, 10, 20, 8, 0, 0);
  const handlers = createAdminEndpointHandlers({
    db,
    auth,
    nowProvider: () => clock,
    logger: { error() {}, warn() {} },
  });

  // 1. Admin A tạo thông báo mới
  const resCreate = createMockRes();
  await handlers.adminManageAnnouncement(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: {
        action: "save",
        isNew: true,
        announcement: {
          id: "ann_keep_author",
          title: "Thông báo gốc",
          content: "Nội dung ban đầu",
          isActive: true,
        },
      },
    },
    resCreate
  );
  assert.equal(resCreate.statusCode, 200);
  const createdDoc = (await db.collection("system_announcements").doc("ann_keep_author").get()).data();
  assert.equal(createdDoc.createdBy, "creator@app.vn");
  assert.equal(createdDoc.updatedBy, "creator@app.vn");
  const originalCreatedAt = createdDoc.createdAt;

  // 2. Admin B chỉnh sửa thông báo (kể cả client truyền createdBy=editor@app.vn) -> PHẢI giữ nguyên createdBy gốc & lưu updatedBy=editor@app.vn
  clock = Date.UTC(2026, 10, 21, 9, 30, 0);
  const resEdit = createMockRes();
  await handlers.adminManageAnnouncement(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_b" },
      body: {
        action: "save",
        isNew: false,
        announcement: {
          id: "ann_keep_author",
          title: "Thông báo đã cập nhật",
          content: "Nội dung mới",
          createdBy: "editor@app.vn",
          createdAt: "2099-01-01T00:00:00.000Z",
          isActive: true,
        },
      },
    },
    resEdit
  );
  assert.equal(resEdit.statusCode, 200);
  const editedDoc = (await db.collection("system_announcements").doc("ann_keep_author").get()).data();
  assert.equal(editedDoc.createdBy, "creator@app.vn");
  assert.equal(editedDoc.createdAt, originalCreatedAt);
  assert.equal(editedDoc.updatedBy, "editor@app.vn");
  assert.equal(editedDoc.title, "Thông báo đã cập nhật");

  // 3. toggle_active & delete với ID không tồn tại -> trả 404, không tạo doc rác, không ghi Audit Log ảo
  const logCountBefore = db._getCol("admin_logs").size;
  const resToggle404 = createMockRes();
  await handlers.adminManageAnnouncement(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_b" },
      body: { action: "toggle_active", announcementId: "missing_ann_id", isActive: false },
    },
    resToggle404
  );
  assert.equal(resToggle404.statusCode, 404);
  assert.equal((await db.collection("system_announcements").doc("missing_ann_id").get()).exists, false);

  const resDel404 = createMockRes();
  await handlers.adminManageAnnouncement(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_b" },
      body: { action: "delete", announcementId: "missing_ann_id" },
    },
    resDel404
  );
  assert.equal(resDel404.statusCode, 404);
  assert.equal(db._getCol("admin_logs").size, logCountBefore);
});

