const test = require("node:test");
const assert = require("node:assert/strict");
const {
  validateConfigPayloadServerSide,
  validateKnowledgeArticleServerSide,
  verifyAdminCallerWithDeps,
  createAdminEndpointHandlers,
} = require("../admin_helpers");

/**
 * In-memory Firestore mock hỗ trợ collection/doc/get/set/update/add/delete/runTransaction
 * phục vụ kiểm thử đơn vị độc lập các Cloud Functions trong `admin_helpers.js`.
 */
class FakeFirestore {
  constructor(initialData = {}) {
    this.collections = new Map();
    this._autoId = 1;
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
    return {
      doc(id) {
        const docId = id || `auto_${store._autoId++}`;
        return {
          id: docId,
          _colName: name,
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
      async add(payload) {
        const docId = `auto_${store._autoId++}`;
        store._getCol(name).set(docId, structuredClone(payload));
        return { id: docId };
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
  return {
    async verifyIdToken(token) {
      if (!verifiedTokens[token]) {
        throw new Error("Invalid ID token");
      }
      return structuredClone(verifiedTokens[token]);
    },
    async getUser(uid) {
      if (!userRecords.has(uid)) {
        return { uid, customClaims: {} };
      }
      return structuredClone(userRecords.get(uid));
    },
    async setCustomUserClaims(uid, claims) {
      const prev = userRecords.get(uid) || { uid };
      userRecords.set(uid, { ...prev, customClaims: structuredClone(claims) });
    },
    _getStoredUser(uid) {
      return userRecords.get(uid);
    },
  };
}

function createMockRes() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function validHeuristicsPayload(overrides = {}) {
  return {
    categorySpikeRatio: 0.3,
    categoryIncomeShareThreshold: 0.25,
    minRecommendedSavingRate: 0.2,
    incomeDropWarningRatio: 0.2,
    incomeDropCriticalRatio: 0.4,
    defaultSavingRateNoGoal: 0.15,
    flexibleSpendFloorRatio: 0.7,
    planBudgetAdherenceWeight: 0.6,
    budgetNearLimitRatio: 0.8,
    categoryForecastWarningRatio: 1.3,
    categoryForecastCriticalRatio: 1.6,
    categoryForecastMinDiffVnd: 100000,
    healthNegativeBalancePenalty: 25,
    healthBudgetExceededPenalty: 15,
    healthBudgetAtRiskPenalty: 10,
    txAnomalyMinDiffVnd: 100000,
    txAnomalyWarningMultiplier: 2.0,
    txAnomalyCriticalMultiplier: 4.0,
    ...overrides,
  };
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

test("validateConfigPayloadServerSide: kiểm chặt transaction_rules & toàn bộ 18 tham số financial_heuristics", () => {
  // 1. Chặn vô hiệu hóa built-in keywords
  const disabledErrs = validateConfigPayloadServerSide("transaction_rules", {
    disabledBuiltInKeywords: ["grab"],
  });
  assert.ok(disabledErrs.some((e) => e.includes("Built-in Keywords")));

  // 2. Chặn trùng từ khóa không dấu & xung đột chéo nhóm bảo vệ
  const conflictErrs = validateConfigPayloadServerSide("transaction_rules", {
    addedExpenseKeywords: {
      "an uong": ["Cà Phê", "Grab"],
    },
  });
  assert.ok(conflictErrs.some((e) => e.includes("ca phe")));
  assert.ok(conflictErrs.some((e) => e.includes("grab")));

  // 3. Chặn ghi đè provider hệ thống & sai walletType
  const providerErrs = validateConfigPayloadServerSide("transaction_rules", {
    customPaymentProviders: [
      {
        key: "momo",
        displayLabel: "Fake MoMo",
        walletType: "crypto",
        receiptKeywords: ["momo new"],
      },
    ],
  });
  assert.ok(providerErrs.some((e) => e.includes("momo")));
  assert.ok(providerErrs.some((e) => e.includes("walletType")));

  // 4. Hợp lệ: từ khóa mới sạch + custom provider isActive: false + disabledAdminKeywords
  const okRulesErrs = validateConfigPayloadServerSide("transaction_rules", {
    addedExpenseKeywords: {
      "an uong": ["Phê La", "Katinat"],
    },
    disabledAdminKeywords: ["katinat"],
    customPaymentProviders: [
      {
        key: "kredivo",
        displayLabel: "Kredivo",
        walletType: "eWallet",
        isActive: false,
        receiptKeywords: ["kredivo"],
        walletNameAliases: ["kredivo"],
      },
    ],
  });
  assert.deepEqual(okRulesErrs, []);

  // 5. Kiểm tra financial_heuristics toàn diện (kể cả số nguyên & cross-field incomeDrop)
  const heurBad = validateConfigPayloadServerSide(
    "financial_heuristics",
    validHeuristicsPayload({
      incomeDropWarningRatio: 0.35,
      incomeDropCriticalRatio: 0.4, // Chênh < 0.10 -> lỗi
      healthNegativeBalancePenalty: 25.5, // Không phải số nguyên -> lỗi
      txAnomalyMinDiffVnd: 9999999, // Vượt max 500000 -> lỗi
    })
  );
  assert.ok(heurBad.length >= 3);
  assert.deepEqual(
    validateConfigPayloadServerSide("financial_heuristics", validHeuristicsPayload()),
    []
  );
});

test("adminPublishKnowledgeBase: kiểm schema, xuất bản nguyên tử và tắt isActive không mất lịch sử", async () => {
  const db = new FakeFirestore({
    users: {
      admin1: { email: "admin@app.vn", name: "Admin", role: "admin", status: "active" },
    },
    financial_knowledge_drafts: {
      kb_bad: {
        articleId: "kb_bad",
        title: "Bài sai schema",
        topic: "crypto_trading",
        triggerCondition: "unknown_trigger",
        priority: 99,
        summaryForUser: "a".repeat(260),
        aiGroundingSnippet: "b".repeat(310),
        suggestedPrompts: ["1", "2", "3", "4"],
        isActive: true,
      },
      kb_good: {
        articleId: "kb_good",
        title: "Quy tắc quỹ dự phòng 3-6 tháng",
        topic: "saving_strategy",
        triggerCondition: "low_saving_rate",
        priority: 9,
        summaryForUser: "Nên duy trì quỹ dự phòng tương đương 3-6 tháng chi thiết yếu.",
        aiGroundingSnippet: "Khuyến nghị người dùng trích quỹ dự phòng trước khi tăng chi linh hoạt.",
        suggestedPrompts: ["Tôi cần quỹ dự phòng bao nhiêu tiền?"],
        isActive: true,
      },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: { tok_a: { uid: "admin1", email: "admin@app.vn", admin: true } },
  });
  const handlers = createAdminEndpointHandlers({ db, auth, logger: { error() {}, warn() {} } });

  // Draft sai schema -> 400 + validationErrors, không tạo bản published
  const resBad = createMockRes();
  await handlers.adminPublishKnowledgeBase(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { articleId: "kb_bad" },
    },
    resBad
  );
  assert.equal(resBad.statusCode, 400);
  assert.ok(resBad.body.validationErrors.length >= 5);
  assert.equal((await db.collection("financial_knowledge_published").doc("kb_bad").get()).exists, false);

  // Draft chuẩn -> 200 publishedVersion 1 + ghi admin_logs
  const resGood = createMockRes();
  await handlers.adminPublishKnowledgeBase(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { articleId: "kb_good", changeNote: "Xuất bản lần 1" },
    },
    resGood
  );
  assert.equal(resGood.statusCode, 200);
  assert.equal(resGood.body.publishedVersion, 1);
  assert.equal(resGood.body.isActive, true);

  const pubDoc1 = await db.collection("financial_knowledge_published").doc("kb_good").get();
  const createdAtFirst = pubDoc1.data().createdAt;

  // Toggle isActive = false -> tăng version lên 2, giữ nguyên lịch sử & createdAt
  const resDisable = createMockRes();
  await handlers.adminPublishKnowledgeBase(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { articleId: "kb_good", action: "toggle_active", isActive: false },
    },
    resDisable
  );
  assert.equal(resDisable.statusCode, 200);
  assert.equal(resDisable.body.publishedVersion, 2);
  assert.equal(resDisable.body.isActive, false);

  const pubDoc2 = await db.collection("financial_knowledge_published").doc("kb_good").get();
  assert.equal(pubDoc2.data().createdAt, createdAtFirst);

  const logs = Array.from(db._getCol("admin_logs").values());
  assert.equal(logs.length, 2);
  assert.ok(logs.every((l) => l.action === "PUBLISH_KNOWLEDGE" && l.targetType === "knowledge"));
});

test("adminRunSandbox: dùng Secret Manager server-side, fallback model, check JSON, rate-limit và không lộ API key", async () => {
  const SECRET_KEY = "AIzaSyFAKE_SUPER_SECRET_NEVER_LEAK";
  const db = new FakeFirestore({
    users: {
      admin1: { email: "admin@app.vn", role: "admin", status: "active" },
    },
  });
  const auth = createFakeAuth({
    verifiedTokens: { tok_a: { uid: "admin1", email: "admin@app.vn", admin: true } },
  });

  const calledUrls = [];
  let failPrimary = true;
  const fakeFetch = async (url, opts) => {
    calledUrls.push({ url, apiKeyHeader: opts.headers["x-goog-api-key"] });
    if (failPrimary && url.includes("gemini-3.5-flash:")) {
      failPrimary = false;
      return {
        ok: false,
        status: 503,
        async json() {
          return { error: { message: "Model temporarily overloaded" } };
        },
      };
    }
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: JSON.stringify({
                      executiveSummary: "Chi tiêu ổn định theo mức thận trọng.",
                      behavioralInsights: ["Ăn uống chiếm 30% ngân sách linh hoạt."],
                      categoryActionTips: { "Ăn uống": "Giữ hạn mức 3.000.000đ/tháng" },
                      savingStrategyNote: "Trích 4.000.000đ đầu tháng.",
                    }),
                  },
                ],
              },
            },
          ],
        };
      },
    };
  };

  const handlers = createAdminEndpointHandlers({
    db,
    auth,
    fetchImpl: fakeFetch,
    geminiApiKeyGetter: async () => SECRET_KEY,
    sandboxRateLimitMaxCalls: 2,
    logger: { error() {}, warn() {} },
  });

  // 1. Chặn client gửi kèm secret key hoặc userId thật
  const resLeakAttempt = createMockRes();
  await handlers.adminRunSandbox(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { apiKey: "client_key", prompt: "hello" },
    },
    resLeakAttempt
  );
  assert.equal(resLeakAttempt.statusCode, 400);

  // 2. Chặn model/temperature ngoài khoảng [0.1, 0.8]
  const resInvalidModel = createMockRes();
  await handlers.adminRunSandbox(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: {
        primaryModel: "gemini-1.0-pro-legacy",
        temperature: 0.05,
        prompt: "hello",
      },
    },
    resInvalidModel
  );
  assert.equal(resInvalidModel.statusCode, 400);

  // 3. Chạy thành công với fallback model & kiểm định JSON contract
  const resOk = createMockRes();
  await handlers.adminRunSandbox(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: {
        mode: "structured_plan_json",
        primaryModel: "gemini-3.5-flash",
        fallbackModels: ["gemini-3.5-flash-lite"],
        temperature: 0.35,
        prompt: "Hãy trả JSON kế hoạch tháng cho Synthetic Persona",
        expectStructuredPlanJson: true,
        persona: { id: "sb_1", label: "Sinh viên" },
      },
    },
    resOk
  );
  assert.equal(resOk.statusCode, 200);
  assert.equal(resOk.body.modelUsed, "gemini-3.5-flash-lite");
  assert.deepEqual(resOk.body.triedModels, ["gemini-3.5-flash", "gemini-3.5-flash-lite"]);
  assert.equal(resOk.body.jsonValid, true);
  assert.equal(calledUrls[0].apiKeyHeader, SECRET_KEY);
  assert.equal(JSON.stringify(resOk.body).includes(SECRET_KEY), false);

  const logsJson = JSON.stringify(Array.from(db._getCol("admin_logs").values()));
  assert.equal(logsJson.includes(SECRET_KEY), false);

  // 4. Rate limit: 2 lần ok -> lần 3 bị 429
  const resOk2 = createMockRes();
  await handlers.adminRunSandbox(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { primaryModel: "gemini-3.5-flash", temperature: 0.3, prompt: "ping" },
    },
    resOk2
  );
  assert.equal(resOk2.statusCode, 200);

  const resRateLimit = createMockRes();
  await handlers.adminRunSandbox(
    {
      method: "POST",
      headers: { authorization: "Bearer tok_a" },
      body: { primaryModel: "gemini-3.5-flash", temperature: 0.3, prompt: "ping 3" },
    },
    resRateLimit
  );
  assert.equal(resRateLimit.statusCode, 429);
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
