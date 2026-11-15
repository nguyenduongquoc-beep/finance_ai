const test = require("node:test");
const assert = require("node:assert/strict");

const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST chưa được thiết lập. Chạy qua `firebase emulators:exec --only firestore --project demo-finance-ai-staging \"node --test functions/test/firestore_rules.test.js\"`."
  );
}

const projectId = process.env.GCLOUD_PROJECT || "demo-finance-ai-staging";
const baseDocUrl = `http://${host}/v1/projects/${projectId}/databases/(default)/documents`;
const baseRootUrl = `http://${host}/v1/projects/${projectId}/databases/(default)`;

function makeToken(uid, claims = {}) {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(
    JSON.stringify({
      iss: `https://securetoken.google.com/${projectId}`,
      aud: projectId,
      auth_time: now,
      user_id: uid,
      sub: uid,
      iat: now,
      exp: now + 3600,
      firebase: { identities: {}, sign_in_provider: "password" },
      ...claims,
    })
  ).toString("base64url");
  return `${header}.${payload}.`;
}

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === "boolean") return { booleanValue: val };
  if (typeof val === "number") {
    return Number.isInteger(val) ? { integerValue: String(val) } : { doubleValue: val };
  }
  if (typeof val === "string") return { stringValue: val };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(toFirestoreValue) } };
  }
  if (typeof val === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function toFirestoreDoc(data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    fields[k] = toFirestoreValue(v);
  }
  return { fields };
}

async function fsRequest(method, path, { token = null, body = null, query = "" } = {}) {
  const url = `${baseDocUrl}/${path}${query}`;
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== null) headers["Content-Type"] = "application/json";

  const res = await fetch(url, {
    method,
    headers,
    body: body !== null ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, ok: res.ok, json };
}

async function seedDoc(path, data) {
  const res = await fsRequest("PATCH", path, {
    token: "owner",
    body: toFirestoreDoc(data),
  });
  if (!res.ok) {
    throw new Error(`Không thể seed ${path}: ${res.status} ${JSON.stringify(res.json)}`);
  }
}

async function seedDeleteDoc(path) {
  const res = await fsRequest("DELETE", path, { token: "owner" });
  if (!res.ok && res.status !== 404) {
    throw new Error(`Không thể xóa seed ${path}: ${res.status} ${JSON.stringify(res.json)}`);
  }
}

async function getDoc(path, token) {
  return fsRequest("GET", path, { token });
}

async function createDoc(collectionPath, docId, data, token) {
  return fsRequest("POST", collectionPath, {
    token,
    query: `?documentId=${encodeURIComponent(docId)}`,
    body: toFirestoreDoc(data),
  });
}

async function updateDoc(path, data, token, updateFields = null) {
  let query = "";
  if (Array.isArray(updateFields) && updateFields.length > 0) {
    query = "?" + updateFields.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join("&");
  }
  return fsRequest("PATCH", path, {
    token,
    query,
    body: toFirestoreDoc(data),
  });
}

async function deleteDoc(path, token) {
  return fsRequest("DELETE", path, { token });
}

async function runQuery(structuredQuery, token) {
  const url = `${baseRootUrl}/documents:runQuery`;
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ structuredQuery }),
  });
  const json = await res.json();
  return { status: res.status, ok: res.ok, json };
}

function expectDenied(res, context) {
  assert.equal(
    res.status,
    403,
    `${context}: kỳ vọng 403 PERMISSION_DENIED, nhận ${res.status} (${JSON.stringify(res.json)})`
  );
}

function expectAllowed(res, context) {
  assert.ok(res.ok, `${context}: kỳ vọng 2xx, nhận ${res.status} (${JSON.stringify(res.json)})`);
}

const TOKEN_USER_A = makeToken("user_a", { email: "user_a@staging.test" });
const TOKEN_USER_B = makeToken("user_b", { email: "user_b@staging.test" });
const TOKEN_USER_NEW = makeToken("user_new", { email: "user_new@staging.test" });
const TOKEN_USER_UNSEEDED = makeToken("user_unseeded", { email: "user_unseeded@staging.test" });
const TOKEN_LOCKED_USER = makeToken("locked_u", { email: "locked_u@staging.test" });
const TOKEN_ADMIN = makeToken("admin_1", { email: "admin@staging.test", admin: true });
const TOKEN_ADMIN_DELETED_DOC = makeToken("admin_deleted_doc", {
  email: "deleted_admin@staging.test",
  admin: true,
});
const TOKEN_ADMIN_NO_STATUS = makeToken("admin_no_status", {
  email: "nostatus_admin@staging.test",
  admin: true,
});
const TOKEN_ADMIN_NO_CLAIM = makeToken("admin_db", { email: "admin_db@staging.test" });
const TOKEN_LOCKED_ADMIN = makeToken("locked_adm", {
  email: "locked_adm@staging.test",
  admin: true,
});

test.before(async () => {
  await seedDoc("users/user_a", {
    uid: "user_a",
    email: "user_a@staging.test",
    name: "User A",
    role: "user",
    status: "active",
  });
  await seedDoc("users/user_b", {
    uid: "user_b",
    email: "user_b@staging.test",
    name: "User B",
    role: "user",
    status: "active",
  });
  await seedDoc("users/locked_u", {
    uid: "locked_u",
    email: "locked_u@staging.test",
    name: "Locked User",
    role: "user",
    status: "locked",
  });
  await seedDoc("users/admin_1", {
    uid: "admin_1",
    email: "admin@staging.test",
    name: "Admin 1",
    role: "admin",
    status: "active",
  });
  await seedDoc("users/admin_db", {
    uid: "admin_db",
    email: "admin_db@staging.test",
    name: "Admin DB Role",
    role: "admin",
    status: "active",
  });
  await seedDoc("users/admin_no_status", {
    uid: "admin_no_status",
    email: "nostatus_admin@staging.test",
    name: "Admin Missing Status",
    role: "admin",
  });
  await seedDoc("users/locked_adm", {
    uid: "locked_adm",
    email: "locked_adm@staging.test",
    name: "Locked Admin",
    role: "admin",
    status: "locked",
  });
  // Tạo rồi xóa `users/admin_deleted_doc` để mô phỏng admin từng tồn tại nhưng đã bị xóa hồ sơ
  await seedDoc("users/admin_deleted_doc", {
    uid: "admin_deleted_doc",
    email: "deleted_admin@staging.test",
    role: "admin",
    status: "active",
  });
  await seedDeleteDoc("users/admin_deleted_doc");

  await seedDoc("draft_configs/ai_runtime", {
    configType: "ai_runtime",
    draftPayload: { temperature: 0.4 },
    draftHash: "h1",
    updatedAt: "2026-11-15T00:00:00Z",
    updatedBy: "admin_1",
  });
  await seedDoc("published_configs/ai_runtime", {
    configType: "ai_runtime",
    version: 1,
    payload: { temperature: 0.4 },
  });
  await seedDoc("_sandbox_verifications/ai_runtime", {
    configType: "ai_runtime",
    verifiedDraftHash: "h1",
    verificationSignature: "sig",
  });
  await seedDoc("config_versions/ai_runtime_v1", {
    versionId: "ai_runtime_v1",
    configType: "ai_runtime",
    versionNumber: 1,
  });

  await seedDoc("financial_knowledge_drafts/kb_1", {
    articleId: "kb_1",
    title: "Quỹ dự phòng 6 tháng",
    topic: "saving_strategy",
    triggerCondition: "always",
    priority: 5,
    summaryForUser: "Duy trì quỹ dự phòng.",
    aiGroundingSnippet: "Luôn ưu tiên quỹ dự phòng 6 tháng.",
    isActive: true,
  });
  await seedDoc("financial_knowledge_published/kb_1", {
    articleId: "kb_1",
    title: "Quỹ dự phòng 6 tháng",
    isActive: true,
    publishedVersion: 1,
  });
  await seedDoc("admin_logs/log_1", {
    adminId: "admin_1",
    action: "PUBLISH_CONFIG",
    source: "cloud_function",
  });
  await seedDoc("system_categories/cat_1", {
    id: "cat_1",
    name: "Ăn uống",
    type: "expense",
    isActive: true,
  });
  await seedDoc("system_announcements/ann_1", {
    id: "ann_1",
    title: "Bảo trì",
    isActive: true,
  });
  await seedDoc("ai_feedback_reports/fb_1", {
    reportId: "fb_1",
    status: "open",
    targetFeature: "ai_chat",
  });
  await seedDoc("_feedback_notification_links/fb_1", {
    reportId: "fb_1",
    uid: "user_a",
  });
  await seedDoc("_server_secrets/sandbox_hmac_v1", {
    secretId: "sandbox_hmac_v1",
    secretValue: "secret",
  });

  await seedDoc("wallets/w_a", { userId: "user_a", walletName: "Cash", balance: 100000 });
  await seedDoc("wallets/w_locked", {
    userId: "locked_u",
    walletName: "Locked Cash",
    balance: 50000,
  });
  await seedDoc("categories/c_a", { userId: "user_a", name: "Food", type: "expense" });
  await seedDoc("transactions/tx_a", { userId: "user_a", walletId: "w_a", amount: 25000 });
  await seedDoc("budgets/b_a", { userId: "user_a", amount: 500000 });
  await seedDoc("savingGoals/g_a", { userId: "user_a", targetAmount: 1000000 });
  await seedDoc("monthly_plans/mp_a", { userId: "user_a", targetMonth: "2026-11" });
  await seedDoc("notifications/n_a", { userId: "user_a", title: "Note A" });
  await seedDoc("recurringTransactions/r_a", { userId: "user_a", title: "Rent" });
  await seedDoc("recurringTransactionOccurrences/ro_a", {
    userId: "user_a",
    scheduleId: "r_a",
  });
  await seedDoc("users/user_a/quickTemplates/qt_a", { name: "Coffee", amount: 30000 });
  await seedDoc("users/user_a/chat_sessions/cs_a", { title: "Chat 1" });
  await seedDoc("users/user_a/monthly_plans/ump_a", { month: "2026-11" });
});

test("Giai đoạn 4A Case 1: Admin có claim và users/{uid} active được phép truy cập đúng phạm vi Admin, vẫn bị chặn dữ liệu cá nhân", async () => {
  expectAllowed(await getDoc("users/user_a", TOKEN_ADMIN), "active admin read users/user_a");
  expectAllowed(await getDoc("admin_logs/log_1", TOKEN_ADMIN), "active admin read admin_logs");
  expectAllowed(await getDoc("draft_configs/ai_runtime", TOKEN_ADMIN), "active admin read draft_configs");
  expectAllowed(
    await getDoc("financial_knowledge_drafts/kb_1", TOKEN_ADMIN),
    "active admin read financial_knowledge_drafts"
  );
  expectAllowed(
    await getDoc("_sandbox_verifications/ai_runtime", TOKEN_ADMIN),
    "active admin read _sandbox_verifications"
  );
  expectAllowed(
    await getDoc("config_versions/ai_runtime_v1", TOKEN_ADMIN),
    "active admin read config_versions"
  );
  expectAllowed(
    await getDoc("ai_feedback_reports/fb_1", TOKEN_ADMIN),
    "active admin read ai_feedback_reports"
  );

  // Vẫn bị chặn dữ liệu tài chính cá nhân và secret nội bộ
  expectDenied(await getDoc("transactions/tx_a", TOKEN_ADMIN), "active admin read user tx");
  expectDenied(
    await getDoc("_server_secrets/sandbox_hmac_v1", TOKEN_ADMIN),
    "active admin read _server_secrets"
  );
});

test("Giai đoạn 4A Case 2: Admin có claim admin=true nhưng users/{uid} bị xóa hoặc thiếu status=='active' phải bị TỪ CHỐI quyền Admin", async () => {
  const adminTargets = [
    ["users/user_a", "other user profile"],
    ["admin_logs/log_1", "admin_logs"],
    ["draft_configs/ai_runtime", "draft_configs"],
    ["financial_knowledge_drafts/kb_1", "financial_knowledge_drafts"],
    ["_sandbox_verifications/ai_runtime", "_sandbox_verifications"],
    ["config_versions/ai_runtime_v1", "config_versions"],
    ["ai_feedback_reports/fb_1", "ai_feedback_reports"],
  ];

  for (const [path, label] of adminTargets) {
    expectDenied(
      await getDoc(path, TOKEN_ADMIN_DELETED_DOC),
      `claim-only admin with deleted users/{uid} read ${label}`
    );
    expectDenied(
      await getDoc(path, TOKEN_ADMIN_NO_STATUS),
      `admin without status=='active' read ${label}`
    );
  }

  expectDenied(
    await updateDoc(
      "draft_configs/ai_runtime",
      {
        configType: "ai_runtime",
        draftPayload: { temperature: 0.6 },
        draftHash: "h_hijack",
        updatedAt: "2026-11-15T02:00:00Z",
        updatedBy: "admin_deleted_doc",
      },
      TOKEN_ADMIN_DELETED_DOC
    ),
    "claim-only admin with deleted users/{uid} write draft_configs"
  );
});

test("Giai đoạn 4A Case 3: Admin có claim admin=true nhưng status=='locked' bị TỪ CHỐI quyền Admin và quyền Active User", async () => {
  expectDenied(await getDoc("users/user_a", TOKEN_LOCKED_ADMIN), "locked admin read users/user_a");
  expectDenied(await getDoc("admin_logs/log_1", TOKEN_LOCKED_ADMIN), "locked admin read admin_logs");
  expectDenied(
    await getDoc("draft_configs/ai_runtime", TOKEN_LOCKED_ADMIN),
    "locked admin read draft_configs"
  );
  expectDenied(
    await getDoc("ai_feedback_reports/fb_1", TOKEN_LOCKED_ADMIN),
    "locked admin read ai_feedback_reports"
  );
  expectDenied(
    await getDoc("wallets/w_locked", TOKEN_LOCKED_USER),
    "locked regular user read own wallet"
  );
  expectAllowed(
    await getDoc("draft_configs/ai_runtime", TOKEN_ADMIN_NO_CLAIM),
    "active db-role admin read draft_configs"
  );
});

test("Giai đoạn 4A Case 4: User thường bị TỪ CHỐI mọi dữ liệu Admin và không thể đọc/sửa hồ sơ người khác", async () => {
  expectDenied(await getDoc("users/user_b", TOKEN_USER_A), "user_a read users/user_b");
  expectDenied(await getDoc("admin_logs/log_1", TOKEN_USER_A), "user read admin_logs");
  expectDenied(await getDoc("draft_configs/ai_runtime", TOKEN_USER_A), "user read draft_configs");
  expectDenied(
    await getDoc("financial_knowledge_drafts/kb_1", TOKEN_USER_A),
    "user read kb drafts"
  );
  expectDenied(
    await getDoc("_sandbox_verifications/ai_runtime", TOKEN_USER_A),
    "user read sandbox_verifications"
  );
  expectDenied(await getDoc("config_versions/ai_runtime_v1", TOKEN_USER_A), "user read config_versions");
  expectDenied(await getDoc("ai_feedback_reports/fb_1", TOKEN_USER_A), "user read ai_feedback_reports");
});

test("Giai đoạn 4A Case 5: User mới chưa có document users/{uid} giữ tương thích luồng đăng ký, nhưng không truy cập được dữ liệu Admin và không tự nâng quyền", async () => {
  // User mới chưa có document users/{uid} vẫn đọc được dữ liệu public sau đăng nhập và tạo dữ liệu cá nhân hợp lệ
  expectAllowed(
    await getDoc("published_configs/ai_runtime", TOKEN_USER_UNSEEDED),
    "unseeded new user read published_configs"
  );
  expectAllowed(
    await getDoc("financial_knowledge_published/kb_1", TOKEN_USER_UNSEEDED),
    "unseeded new user read published KB"
  );
  expectAllowed(
    await createDoc(
      "wallets",
      "w_unseeded",
      { userId: "user_unseeded", walletName: "Ví mới", balance: 0 },
      TOKEN_USER_UNSEEDED
    ),
    "unseeded new user create own wallet via isActiveUser()"
  );
  expectAllowed(
    await getDoc("wallets/w_unseeded", TOKEN_USER_UNSEEDED),
    "unseeded new user read own wallet via isActiveUser()"
  );

  // Nhưng User mới chưa có document tuyệt đối không có quyền Admin
  expectDenied(
    await getDoc("admin_logs/log_1", TOKEN_USER_UNSEEDED),
    "unseeded user denied admin_logs"
  );
  expectDenied(
    await getDoc("draft_configs/ai_runtime", TOKEN_USER_UNSEEDED),
    "unseeded user denied draft_configs"
  );

  // Không thể tự nâng role/status khi tạo hoặc cập nhật users/{uid}
  expectDenied(
    await createDoc(
      "users",
      "user_new",
      { uid: "user_new", role: "admin", status: "active" },
      TOKEN_USER_NEW
    ),
    "create user_new role=admin"
  );
  expectDenied(
    await createDoc(
      "users",
      "user_new",
      { uid: "user_new", role: "user", status: "locked" },
      TOKEN_USER_NEW
    ),
    "create user_new status=locked"
  );
  expectAllowed(
    await createDoc(
      "users",
      "user_new",
      { uid: "user_new", name: "New", role: "user", status: "active" },
      TOKEN_USER_NEW
    ),
    "create valid user_new"
  );
});

test("Client không thể tự sửa role/status và Draft/Published/Feedback Rules vẫn giữ nguyên", async () => {
  expectAllowed(
    await updateDoc(
      "users/user_a",
      {
        uid: "user_a",
        email: "user_a@staging.test",
        name: "User A Updated",
        role: "user",
        status: "active",
      },
      TOKEN_USER_A
    ),
    "user update own name"
  );
  expectDenied(
    await updateDoc(
      "users/user_a",
      {
        uid: "user_a",
        email: "user_a@staging.test",
        name: "User A",
        role: "admin",
        status: "active",
      },
      TOKEN_USER_A
    ),
    "user self-escalate role=admin"
  );
  expectDenied(
    await updateDoc(
      "users/user_a",
      {
        uid: "user_a",
        email: "user_a@staging.test",
        name: "User A",
        role: "user",
        status: "locked",
      },
      TOKEN_USER_A
    ),
    "user self-change status=locked"
  );
  expectDenied(await deleteDoc("users/user_a", TOKEN_USER_A), "delete own user");

  // Admin Client không thể trực tiếp sửa role/status hoặc profile user khác
  expectDenied(await updateDoc("users/user_a", { role: "admin" }, TOKEN_ADMIN, ["role"]), "admin patch user_a role");
  expectDenied(await updateDoc("users/user_a", { status: "locked" }, TOKEN_ADMIN, ["status"]), "admin patch user_a status");
  expectDenied(await updateDoc("users/admin_1", { role: "user" }, TOKEN_ADMIN, ["role"]), "admin patch own role");
  expectDenied(await updateDoc("users/admin_1", { status: "locked" }, TOKEN_ADMIN, ["status"]), "admin patch own status");

  // Client không thể ghi admin_logs, _sandbox_verifications, config_versions, published, ai_feedback_reports
  expectDenied(await createDoc("admin_logs", "fake_a", { action: "FAKE" }, TOKEN_ADMIN), "admin create admin_logs");
  expectDenied(
    await updateDoc("_sandbox_verifications/ai_runtime", { verifiedDraftHash: "fake" }, TOKEN_ADMIN),
    "admin write _sandbox_verifications"
  );
  expectDenied(
    await createDoc("config_versions", "ai_runtime_v2", { versionNumber: 2 }, TOKEN_ADMIN),
    "admin create config_versions"
  );
  expectDenied(
    await updateDoc(
      "draft_configs/ai_runtime",
      {
        configType: "ai_runtime",
        draftPayload: { temperature: 0.5 },
        draftHash: "h2",
        updatedAt: "2026-11-15T01:00:00Z",
        updatedBy: "admin_1",
        verifiedSandboxHash: "h2",
      },
      TOKEN_ADMIN
    ),
    "admin sneak verifiedSandboxHash into draft_configs"
  );
  expectAllowed(
    await updateDoc(
      "draft_configs/ai_runtime",
      {
        configType: "ai_runtime",
        draftPayload: { temperature: 0.5 },
        draftHash: "h2",
        updatedAt: "2026-11-15T01:00:00Z",
        updatedBy: "admin_1",
      },
      TOKEN_ADMIN
    ),
    "admin valid draft_configs update"
  );
  expectDenied(
    await updateDoc("published_configs/ai_runtime", { version: 99 }, TOKEN_ADMIN),
    "admin write published_configs"
  );
  expectDenied(
    await createDoc("ai_feedback_reports", "fb_client", { reportId: "fb_client" }, TOKEN_USER_A),
    "user direct create feedback"
  );
  expectDenied(
    await updateDoc("ai_feedback_reports/fb_1", { status: "resolved" }, TOKEN_ADMIN, ["status"]),
    "admin direct update feedback"
  );

  // Dữ liệu cá nhân tách biệt tuyệt đối giữa các User và Admin
  const privateCollections = [
    ["wallets", "w_a"],
    ["categories", "c_a"],
    ["transactions", "tx_a"],
    ["budgets", "b_a"],
    ["savingGoals", "g_a"],
    ["monthly_plans", "mp_a"],
    ["notifications", "n_a"],
    ["recurringTransactions", "r_a"],
    ["recurringTransactionOccurrences", "ro_a"],
    ["users/user_a/quickTemplates", "qt_a"],
    ["users/user_a/chat_sessions", "cs_a"],
    ["users/user_a/monthly_plans", "ump_a"],
  ];
  for (const [col, id] of privateCollections) {
    const path = `${col}/${id}`;
    expectAllowed(await getDoc(path, TOKEN_USER_A), `owner read ${path}`);
    expectDenied(await getDoc(path, TOKEN_USER_B), `user_b read ${path}`);
    expectDenied(await getDoc(path, TOKEN_ADMIN), `admin read ${path}`);
  }
  const adminQueryRes = await runQuery({ from: [{ collectionId: "transactions" }] }, TOKEN_ADMIN);
  expectDenied(adminQueryRes, "admin list transactions query");
  expectDenied(
    await createDoc("transactions", "tx_spoof", { userId: "user_b", amount: 1000 }, TOKEN_USER_A),
    "spoof userId"
  );
  expectDenied(
    await getDoc("_feedback_notification_links/fb_1", TOKEN_ADMIN),
    "admin read feedback links"
  );
});
