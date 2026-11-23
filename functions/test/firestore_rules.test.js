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

async function runQuery(structuredQuery, token, parentPath = "") {
  const url = parentPath
    ? `${baseDocUrl}/${parentPath}:runQuery`
    : `${baseRootUrl}/documents:runQuery`;
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

async function commitWrites(writes, token) {
  const url = `${baseRootUrl}/documents:commit`;
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ writes }),
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

function docName(relPath) {
  return `projects/${projectId}/databases/(default)/documents/${relPath}`;
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
const TOKEN_DEMOTED_ADMIN = makeToken("demoted_adm", {
  email: "demoted_adm@staging.test",
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
  await seedDoc("users/demoted_adm", {
    uid: "demoted_adm",
    email: "demoted_adm@staging.test",
    name: "Demoted Admin",
    role: "user",
    status: "active",
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

test("Giai đoạn 4A Case 1: Admin có role=='admin' & status=='active' truy cập đúng phạm vi cốt lõi trên Spark, bị chặn tuyệt đối dữ liệu tài chính riêng tư & chặn ngay Admin vừa bị hạ quyền dù JWT cũ còn admin=true", async () => {
  // Admin đang hoạt động (kể cả không có custom claim trên Spark) đọc được hồ sơ chính mình & danh sách users phục vụ vận hành
  expectAllowed(await getDoc("users/admin_1", TOKEN_ADMIN), "active admin read own users/admin_1");
  expectAllowed(await getDoc("users/user_a", TOKEN_ADMIN), "active admin read users/user_a for Spark directory");
  expectAllowed(
    await runQuery({ from: [{ collectionId: "users" }] }, TOKEN_ADMIN),
    "active admin list users collection for Spark directory"
  );
  expectAllowed(
    await getDoc("users/user_a", TOKEN_ADMIN_NO_CLAIM),
    "active Spark db-role admin read users/user_a without custom claim"
  );

  // Admin vừa bị hạ quyền (role='user') nhưng JWT cũ vẫn còn claim admin=true -> bị TỪ CHỐI tức thì
  expectDenied(await getDoc("admin_logs/log_1", TOKEN_DEMOTED_ADMIN), "demoted admin with stale claim denied admin_logs");
  expectDenied(await getDoc("users/user_a", TOKEN_DEMOTED_ADMIN), "demoted admin with stale claim denied users/user_a");

  expectAllowed(await getDoc("admin_logs/log_1", TOKEN_ADMIN), "active admin read admin_logs");
  expectAllowed(await getDoc("system_categories/cat_1", TOKEN_ADMIN), "active admin read system_categories");
  expectAllowed(await getDoc("system_announcements/ann_1", TOKEN_ADMIN), "active admin read system_announcements");

  // Các collection Quản trị AI & Tri thức đã gỡ bỏ -> khóa tuyệt đối cả đọc lẫn ghi
  const lockedLegacyCollections = [
    "published_configs/ai_runtime",
    "financial_knowledge_published/kb_1",
    "draft_configs/ai_runtime",
    "financial_knowledge_drafts/kb_1",
    "_sandbox_verifications/ai_runtime",
    "config_versions/ai_runtime_v1",
    "ai_feedback_reports/fb_1",
    "_feedback_notification_links/fb_1",
    "_server_secrets/sandbox_hmac_v1",
  ];
  for (const path of lockedLegacyCollections) {
    expectDenied(await getDoc(path, TOKEN_ADMIN), `active admin denied locked collection ${path}`);
  }

  // Vẫn bị chặn TUYỆT ĐỐI dữ liệu tài chính cá nhân của người dùng
  expectDenied(await getDoc("transactions/tx_a", TOKEN_ADMIN), "active admin read user tx");
  expectDenied(await getDoc("wallets/w_a", TOKEN_ADMIN), "active admin read user wallet");
  expectDenied(await getDoc("users/user_a/chat_sessions/cs_a", TOKEN_ADMIN), "active admin read user AI chat");
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
    await getDoc("admin_logs/log_1", TOKEN_ADMIN_NO_CLAIM),
    "active db-role admin read admin_logs"
  );
});

test("Giai đoạn 4A Case 4: User thường bị TỪ CHỐI mọi dữ liệu Admin và không thể đọc/sửa hồ sơ người khác", async () => {
  expectDenied(await getDoc("users/user_b", TOKEN_USER_A), "user_a read users/user_b");
  expectDenied(await getDoc("admin_logs/log_1", TOKEN_USER_A), "user read admin_logs");
  expectDenied(await getDoc("published_configs/ai_runtime", TOKEN_USER_A), "user read locked published_configs");
  expectDenied(
    await getDoc("financial_knowledge_published/kb_1", TOKEN_USER_A),
    "user read locked kb published"
  );
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
  // User mới chưa có document users/{uid} vẫn đọc được danh mục/thông báo hệ thống và tạo dữ liệu cá nhân hợp lệ
  expectAllowed(
    await getDoc("system_categories/cat_1", TOKEN_USER_UNSEEDED),
    "unseeded new user read system_categories"
  );
  expectAllowed(
    await getDoc("system_announcements/ann_1", TOKEN_USER_UNSEEDED),
    "unseeded new user read system_announcements"
  );
  expectDenied(
    await getDoc("published_configs/ai_runtime", TOKEN_USER_UNSEEDED),
    "unseeded new user denied locked published_configs"
  );
  expectDenied(
    await getDoc("financial_knowledge_published/kb_1", TOKEN_USER_UNSEEDED),
    "unseeded new user denied locked published KB"
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

  // Không thể tự nâng role/status hoặc ghi trường tài chính lên root users/{uid}
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
  expectDenied(
    await createDoc(
      "users",
      "user_new",
      {
        uid: "user_new",
        name: "New",
        role: "user",
        status: "active",
        monthlyIncome: 25000000,
      },
      TOKEN_USER_NEW
    ),
    "create user_new denied financial field monthlyIncome on root users/{uid}"
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
  // Chính chủ được phép tạo/đọc/xóa hồ sơ tài chính riêng tư users/{uid}/private/financial_profile; Admin bị chặn 100%
  expectAllowed(
    await createDoc(
      "users/user_new/private",
      "financial_profile",
      { monthlyIncome: 25000000, savingGoal: "Mua nhà" },
      TOKEN_USER_NEW
    ),
    "owner create private/financial_profile"
  );
  expectDenied(
    await getDoc("users/user_new/private/financial_profile", TOKEN_ADMIN),
    "admin denied reading user private/financial_profile"
  );
  expectDenied(
    await updateDoc(
      "users/user_new/private/financial_profile",
      { monthlyIncome: 0 },
      TOKEN_ADMIN,
      ["monthlyIncome"]
    ),
    "admin denied writing user private/financial_profile"
  );
  expectAllowed(
    await deleteDoc("users/user_new/private/financial_profile", TOKEN_USER_NEW),
    "owner delete own private/financial_profile for self-delete"
  );
  expectAllowed(
    await deleteDoc("users/user_new", TOKEN_USER_NEW),
    "owner delete own users/{uid} for Spark self-delete"
  );
});

test("Client không thể tự sửa role/status và khóa tuyệt đối các collection AI Governance đã gỡ bỏ", async () => {
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
  expectDenied(
    await updateDoc(
      "users/user_a",
      { lockReason: "Tampered" },
      TOKEN_USER_A,
      ["lockReason"]
    ),
    "user denied modifying own lockReason"
  );

  // Admin đang hoạt động (thuần Spark) CHỈ được khóa/mở khóa tài khoản User thường (`role != 'admin'`)
  // với đầy đủ `status`, `lockReason`, `lockedAt == request.time`, `lockedBy`, `updatedAt`.
  // TUYỆT ĐỐI cấm đổi `role`, cấm khóa chính mình, cấm khóa Admin khác và cấm xóa user.
  expectAllowed(
    await commitWrites(
      [
        {
          update: {
            name: docName("users/user_b"),
            fields: toFirestoreDoc({
              status: "locked",
              lockReason: "Vi phạm điều khoản sử dụng",
              lockedBy: "admin@staging.test",
              updatedAt: "2026-11-22T05:00:00Z",
            }).fields,
          },
          updateMask: {
            fieldPaths: ["status", "lockReason", "lockedBy", "updatedAt"],
          },
          updateTransforms: [
            { fieldPath: "lockedAt", setToServerValue: "REQUEST_TIME" },
          ],
        },
      ],
      TOKEN_ADMIN
    ),
    "active admin lock user_b with standardized reason + serverTimestamp"
  );
  expectAllowed(
    await updateDoc(
      "users/user_b",
      {
        status: "active",
        lockReason: null,
        lockedAt: null,
        lockedBy: null,
        updatedAt: "2026-11-22T05:01:00Z",
      },
      TOKEN_ADMIN_NO_CLAIM,
      ["status", "lockReason", "lockedAt", "lockedBy", "updatedAt"]
    ),
    "active Spark db-role admin unlock user_b clearing lock metadata"
  );
  // Cấm đổi vai trò từ Web Admin (gỡ bỏ hoàn toàn luồng Cấp/Hạ quyền Admin)
  expectDenied(
    await updateDoc(
      "users/user_b",
      { role: "admin", updatedAt: "2026-11-22T05:02:00Z" },
      TOKEN_ADMIN,
      ["role", "updatedAt"]
    ),
    "admin denied changing user role from Web Admin"
  );
  // Cấm khóa tài khoản Admin khác (`admin_db`)
  expectDenied(
    await commitWrites(
      [
        {
          update: {
            name: docName("users/admin_db"),
            fields: toFirestoreDoc({
              status: "locked",
              lockReason: "Thử khóa admin khác",
              lockedBy: "admin@staging.test",
              updatedAt: "2026-11-22T05:03:00Z",
            }).fields,
          },
          updateMask: {
            fieldPaths: ["status", "lockReason", "lockedBy", "updatedAt"],
          },
          updateTransforms: [
            { fieldPath: "lockedAt", setToServerValue: "REQUEST_TIME" },
          ],
        },
      ],
      TOKEN_ADMIN
    ),
    "admin denied locking another admin account"
  );

  // Chặn admin sửa trường cá nhân, giá trị không hợp lệ, tự sửa bản thân hoặc xóa user
  expectDenied(
    await updateDoc("users/user_b", { name: "Hacked Name", updatedAt: "2026-11-22T05:04:00Z" }, TOKEN_ADMIN, ["name", "updatedAt"]),
    "admin denied patching other user's personal name"
  );
  expectDenied(
    await updateDoc("users/user_b", { status: "banned", updatedAt: "2026-11-22T05:04:00Z" }, TOKEN_ADMIN, ["status", "updatedAt"]),
    "admin denied invalid status value"
  );
  expectDenied(
    await updateDoc("users/admin_1", { role: "user", updatedAt: "2026-11-22T05:04:00Z" }, TOKEN_ADMIN, ["role", "updatedAt"]),
    "admin denied patching own role"
  );
  expectDenied(
    await updateDoc("users/admin_1", { status: "locked", updatedAt: "2026-11-22T05:04:00Z" }, TOKEN_ADMIN, ["status", "updatedAt"]),
    "admin denied patching own status"
  );
  expectDenied(await deleteDoc("users/user_b", TOKEN_ADMIN), "admin denied deleting user doc directly");

  // Demoted / locked admin bị chặn đổi status của user khác
  expectDenied(
    await updateDoc("users/user_b", { status: "locked", updatedAt: "2026-11-22T05:05:00Z" }, TOKEN_DEMOTED_ADMIN, ["status", "updatedAt"]),
    "demoted admin denied locking user_b"
  );
  expectDenied(
    await updateDoc("users/user_b", { status: "locked", updatedAt: "2026-11-22T05:05:00Z" }, TOKEN_LOCKED_ADMIN, ["status", "updatedAt"]),
    "locked admin denied locking user_b"
  );

  // Danh mục Hệ thống (system_categories): Admin tạo/cập nhật/ẩn-hiện hợp lệ, cấm xóa cứng, cấm user thường ghi
  expectAllowed(
    await createDoc(
      "system_categories",
      "cat_spark_1",
      {
        id: "cat_spark_1",
        name: "Tiền thuê nhà",
        type: "expense",
        icon: "home",
        color: 4293848814,
        isEssential: true,
        isActive: true,
        createdAt: "2026-11-22T05:10:00Z",
        updatedAt: "2026-11-22T05:10:00Z",
      },
      TOKEN_ADMIN
    ),
    "active admin create valid system_category"
  );
  expectAllowed(
    await updateDoc(
      "system_categories/cat_spark_1",
      { isActive: false, updatedAt: "2026-11-22T05:11:00Z" },
      TOKEN_ADMIN_NO_CLAIM,
      ["isActive", "updatedAt"]
    ),
    "active Spark admin toggle system_category isActive"
  );
  expectDenied(
    await createDoc(
      "system_categories",
      "cat_bad",
      {
        id: "cat_bad",
        name: "",
        type: "expense",
        icon: "home",
        color: 4293848814,
        isEssential: false,
        isActive: true,
        createdAt: "2026-11-22T05:10:00Z",
        updatedAt: "2026-11-22T05:10:00Z",
      },
      TOKEN_ADMIN
    ),
    "admin denied creating system_category with empty name"
  );
  expectDenied(
    await deleteDoc("system_categories/cat_spark_1", TOKEN_ADMIN),
    "admin denied hard-deleting system_category"
  );
  expectDenied(
    await createDoc(
      "system_categories",
      "cat_by_user",
      {
        id: "cat_by_user",
        name: "Fake",
        type: "expense",
        icon: "home",
        color: 123,
        isEssential: false,
        isActive: true,
        createdAt: "2026-11-22T05:10:00Z",
        updatedAt: "2026-11-22T05:10:00Z",
      },
      TOKEN_USER_A
    ),
    "regular user denied creating system_category"
  );

  // Thông báo Hệ thống (system_announcements): Admin tạo/sửa (giữ nguyên createdBy)/bật-tắt/xóa, cấm sửa giả createdBy
  expectAllowed(
    await createDoc(
      "system_announcements",
      "ann_spark_1",
      {
        id: "ann_spark_1",
        title: "Bảo trì hệ thống",
        content: "Hệ thống bảo trì từ 02:00 - 03:00.",
        isActive: true,
        createdBy: "admin@staging.test",
        updatedBy: "admin@staging.test",
        createdAt: "2026-11-22T05:12:00Z",
        updatedAt: "2026-11-22T05:12:00Z",
      },
      TOKEN_ADMIN
    ),
    "active admin create valid system_announcement"
  );
  expectDenied(
    await updateDoc(
      "system_announcements/ann_spark_1",
      {
        id: "ann_spark_1",
        title: "Sửa tiêu đề",
        content: "Sửa nội dung",
        isActive: true,
        createdBy: "spoofed@staging.test",
        updatedBy: "admin_db@staging.test",
        createdAt: "2026-11-22T05:12:00Z",
        updatedAt: "2026-11-22T05:13:00Z",
      },
      TOKEN_ADMIN_NO_CLAIM
    ),
    "admin denied overwriting original createdBy on system_announcement"
  );
  expectAllowed(
    await updateDoc(
      "system_announcements/ann_spark_1",
      {
        id: "ann_spark_1",
        title: "Sửa tiêu đề hợp lệ",
        content: "Sửa nội dung hợp lệ",
        isActive: true,
        createdBy: "admin@staging.test",
        updatedBy: "admin_db@staging.test",
        createdAt: "2026-11-22T05:12:00Z",
        updatedAt: "2026-11-22T05:13:00Z",
      },
      TOKEN_ADMIN_NO_CLAIM
    ),
    "admin allowed editing system_announcement while preserving createdBy"
  );
  expectAllowed(
    await deleteDoc("system_announcements/ann_spark_1", TOKEN_ADMIN),
    "active admin delete system_announcement"
  );
  expectDenied(
    await deleteDoc("system_announcements/ann_1", TOKEN_USER_A),
    "regular user denied deleting system_announcement"
  );

  // Nhật ký quản trị (admin_logs): Append-only chuẩn schema (adminId == auth.uid, allowlist action), CẤM giả mạo, CẤM sửa/xóa
  expectDenied(
    await createDoc("admin_logs", "fake_a", { action: "FAKE" }, TOKEN_ADMIN),
    "admin denied invalid admin_logs schema / unallowlisted action"
  );
  expectDenied(
    await createDoc(
      "admin_logs",
      "spoof_admin_log",
      {
        adminId: "admin_db",
        adminEmail: "admin@staging.test",
        action: "LOCK_USER",
        targetType: "user",
        targetId: "user_b",
        targetLabel: "user_b@staging.test",
        result: "success",
        details: "Spoofed adminId",
        source: "admin_web",
        createdAt: "2026-11-22T05:14:00Z",
      },
      TOKEN_ADMIN
    ),
    "admin denied spoofing another adminId in admin_logs"
  );
  expectAllowed(
    await createDoc(
      "admin_logs",
      "valid_spark_log_1",
      {
        adminId: "admin_1",
        adminEmail: "admin@staging.test",
        action: "CREATE_SYSTEM_CATEGORY",
        targetType: "system_category",
        targetId: "cat_spark_1",
        targetLabel: "Tiền thuê nhà",
        result: "success",
        details: "Tạo danh mục mặc định hệ thống.",
        source: "admin_web",
        createdAt: "2026-11-22T05:15:00Z",
      },
      TOKEN_ADMIN
    ),
    "active admin append valid audit log"
  );
  expectDenied(
    await updateDoc("admin_logs/valid_spark_log_1", { details: "Tampered" }, TOKEN_ADMIN, ["details"]),
    "admin denied tampering with existing admin_logs (append-only)"
  );
  expectDenied(
    await deleteDoc("admin_logs/valid_spark_log_1", TOKEN_ADMIN),
    "admin denied deleting existing admin_logs (append-only)"
  );
  expectDenied(
    await createDoc(
      "admin_logs",
      "user_log",
      {
        adminId: "user_a",
        adminEmail: "user_a@staging.test",
        action: "LOCK_USER",
        targetType: "user",
        targetId: "user_b",
        targetLabel: "user_b",
        result: "success",
        details: "User trying to write audit log",
        source: "admin_web",
        createdAt: "2026-11-22T05:15:00Z",
      },
      TOKEN_USER_A
    ),
    "regular user denied creating admin_logs"
  );

  // Các collection AI Governance đã khóa tuyệt đối
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
      },
      TOKEN_ADMIN
    ),
    "admin denied locked draft_configs write"
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

function makeSupportTicketDoc({
  ticketId,
  ticketCode,
  userId = "user_a",
  userName = "User A",
  userEmail = "user_a@staging.test",
  category = "financial_advisory",
  title = "Cần tư vấn phân bổ ngân sách tháng 11",
  description = "Thu nhập tháng này của tôi 15 triệu, muốn tiết kiệm 20% thì nên chia ngân sách thế nào?",
  priority = "normal",
  userImpact = "normal",
  lastMessageId = "msg_1",
  now = "2026-11-19T10:00:00.000Z",
  extra = {},
}) {
  return {
    ticketId,
    ticketCode,
    userId,
    userName,
    userEmail,
    category,
    title,
    description,
    status: "new",
    priority,
    userImpact,
    assignedAdminId: null,
    assignedAdminName: null,
    lastMessageId,
    lastMessagePreview: description.slice(0, 60),
    lastMessageSenderRole: "user",
    lastMessageAt: now,
    unreadByAdmin: true,
    unreadByUser: false,
    createdAt: now,
    updatedAt: now,
    claimedAt: null,
    firstAdminResponseAt: null,
    resolvedAt: null,
    resolvedByRole: null,
    closedAt: null,
    closeReason: null,
    ratingScore: null,
    ratingComment: null,
    ratedAt: null,
    ratingUpdatedAt: null,
    ratingEditCount: 0,
    ...extra,
  };
}

function makeSupportMsgDoc({
  messageId,
  senderId,
  senderRole,
  senderDisplayName,
  body,
  messageType = "text",
  createdAt,
}) {
  return {
    messageId,
    senderId,
    senderRole,
    senderDisplayName,
    body,
    messageType,
    createdAt,
  };
}

function ticketPatchWrite(ticketId, fields) {
  return {
    update: {
      name: docName(`support_tickets/${ticketId}`),
      ...toFirestoreDoc(fields),
    },
    updateMask: {
      fieldPaths: Object.keys(fields),
    },
  };
}

function msgCreateWrite(ticketId, msg) {
  return {
    update: {
      name: docName(`support_tickets/${ticketId}/messages/${msg.messageId}`),
      ...toFirestoreDoc(msg),
    },
    currentDocument: { exists: false },
  };
}

test("Support Center (Spark): Phân quyền User/Admin, ưu tiên, thông tin kỹ thuật, đồng bộ 2 chiều WriteBatch, vòng đời trạng thái, đánh giá & đóng chuẩn", async () => {
  const ticketId = "sup_ticket_a1";
  const now1 = "2026-11-19T10:00:00.000Z";
  const now2 = "2026-11-19T10:05:00.000Z";
  const now3 = "2026-11-19T10:10:00.000Z";
  const now4 = "2026-11-19T10:15:00.000Z";
  const now5 = "2026-11-19T10:20:00.000Z";
  const now6 = "2026-11-19T10:25:00.000Z";
  const now7 = "2026-11-19T10:30:00.000Z";
  const now8 = "2026-11-19T10:35:00.000Z";
  const now9 = "2026-11-19T10:40:00.000Z";
  const now10 = "2026-11-19T10:45:00.000Z";

  const baseTicketA = makeSupportTicketDoc({
    ticketId,
    ticketCode: "SUP-261119-A001",
    userImpact: "high",
    now: now1,
  });
  const firstMsgA = makeSupportMsgDoc({
    messageId: "msg_1",
    senderId: "user_a",
    senderRole: "user",
    senderDisplayName: "User A",
    body: baseTicketA.description,
    messageType: "text",
    createdAt: now1,
  });

  // 1. Chặn giả mạo khi tạo ticket: tự nâng priority, không tạo message kèm, hoặc đính technicalInfo sai nhóm/sai schema
  expectDenied(
    await commitWrites(
      [
        {
          update: {
            name: docName("support_tickets/sup_spoof_priority"),
            ...toFirestoreDoc(
              makeSupportTicketDoc({
                ticketId: "sup_spoof_priority",
                ticketCode: "SUP-261119-SP01",
                priority: "urgent",
                now: now1,
              })
            ),
          },
          currentDocument: { exists: false },
        },
        msgCreateWrite("sup_spoof_priority", firstMsgA),
      ],
      TOKEN_USER_A
    ),
    "user_a self-assign priority=urgent on create denied"
  );

  expectDenied(
    await createDoc(
      "support_tickets",
      "sup_no_first_msg",
      makeSupportTicketDoc({
        ticketId: "sup_no_first_msg",
        ticketCode: "SUP-261119-NM01",
        now: now1,
      }),
      TOKEN_USER_A
    ),
    "user_a create ticket without synchronized first message denied (2-way sync)"
  );

  expectDenied(
    await commitWrites(
      [
        {
          update: {
            name: docName("support_tickets/sup_tech_wrong_cat"),
            ...toFirestoreDoc(
              makeSupportTicketDoc({
                ticketId: "sup_tech_wrong_cat",
                ticketCode: "SUP-261119-TC01",
                category: "app_guide",
                now: now1,
                extra: {
                  technicalInfo: {
                    appVersion: "1.0.0+1",
                    platform: "Android",
                    osVersion: "Android 14",
                    capturedAt: now1,
                  },
                },
              })
            ),
          },
          currentDocument: { exists: false },
        },
        msgCreateWrite("sup_tech_wrong_cat", firstMsgA),
      ],
      TOKEN_USER_A
    ),
    "user_a attach technicalInfo on non-bug_report category denied"
  );

  expectDenied(
    await commitWrites(
      [
        {
          update: {
            name: docName("support_tickets/sup_tech_extra_key"),
            ...toFirestoreDoc(
              makeSupportTicketDoc({
                ticketId: "sup_tech_extra_key",
                ticketCode: "SUP-261119-TK01",
                category: "bug_report",
                now: now1,
                extra: {
                  technicalInfo: {
                    appVersion: "1.0.0+1",
                    platform: "Android",
                    capturedAt: now1,
                    walletBalance: 999999,
                  },
                },
              })
            ),
          },
          currentDocument: { exists: false },
        },
        msgCreateWrite("sup_tech_extra_key", firstMsgA),
      ],
      TOKEN_USER_A
    ),
    "user_a attach disallowed key in technicalInfo denied"
  );

  // Tạo hợp lệ 1 ticket báo lỗi có technicalInfo chuẩn
  const bugTicketId = "sup_ticket_bug1";
  const bugTicket = makeSupportTicketDoc({
    ticketId: bugTicketId,
    ticketCode: "SUP-261119-BG01",
    category: "bug_report",
    title: "Biểu đồ chi tiêu không tải lại",
    description: "Khi thêm giao dịch chi mới, biểu đồ trang chủ vẫn giữ số liệu cũ.",
    userImpact: "blocking",
    now: now1,
    extra: {
      technicalInfo: {
        appVersion: "1.0.0+1",
        platform: "Android",
        osVersion: "Android 14",
        capturedAt: now1,
      },
    },
  });
  expectAllowed(
    await commitWrites(
      [
        {
          update: {
            name: docName(`support_tickets/${bugTicketId}`),
            ...toFirestoreDoc(bugTicket),
          },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          bugTicketId,
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: bugTicket.description,
            createdAt: now1,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "user_a atomic create bug_report with valid technicalInfo"
  );

  // 2. User A tạo yêu cầu chính + tin nhắn đầu tiên trong 1 WriteBatch nguyên tử (đồng bộ 2 chiều)
  expectAllowed(
    await commitWrites(
      [
        {
          update: { name: docName(`support_tickets/${ticketId}`), ...toFirestoreDoc(baseTicketA) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(ticketId, firstMsgA),
      ],
      TOKEN_USER_A
    ),
    "user_a atomic create support ticket + first message"
  );

  // User A đọc/list yêu cầu của chính mình; User B & tài khoản khóa bị chặn tuyệt đối
  expectAllowed(await getDoc(`support_tickets/${ticketId}`, TOKEN_USER_A), "user_a read own ticket");
  expectAllowed(
    await getDoc(`support_tickets/${ticketId}/messages/msg_1`, TOKEN_USER_A),
    "user_a read own ticket message"
  );
  const userAListQuery = {
    from: [{ collectionId: "support_tickets" }],
    where: {
      fieldFilter: {
        field: { fieldPath: "userId" },
        op: "EQUAL",
        value: { stringValue: "user_a" },
      },
    },
    orderBy: [{ field: { fieldPath: "updatedAt" }, direction: "DESCENDING" }],
    limit: 25,
  };
  expectAllowed(await runQuery(userAListQuery, TOKEN_USER_A), "user_a list own support_tickets");
  expectAllowed(
    await runQuery(
      {
        from: [{ collectionId: "support_tickets" }],
        where: {
          fieldFilter: {
            field: { fieldPath: "userId" },
            op: "EQUAL",
            value: { stringValue: "user_unseeded" },
          },
        },
        orderBy: [{ field: { fieldPath: "updatedAt" }, direction: "DESCENDING" }],
        limit: 25,
      },
      TOKEN_USER_UNSEEDED
    ),
    "unseeded user list own support_tickets"
  );
  const missingTicketRes = await getDoc("support_tickets/non_existent_ticket", TOKEN_USER_A);
  assert.equal(missingTicketRes.status, 404, "user_a get non-existent ticket returns 404");
  expectDenied(
    await getDoc("support_tickets/non_existent_ticket", TOKEN_LOCKED_USER),
    "locked user denied non-existent ticket"
  );
  expectDenied(await getDoc(`support_tickets/${ticketId}`, TOKEN_USER_B), "user_b read user_a ticket");
  expectDenied(
    await getDoc(`support_tickets/${ticketId}/messages/msg_1`, TOKEN_USER_B),
    "user_b read user_a message"
  );
  expectDenied(
    await updateDoc(`support_tickets/${ticketId}`, { unreadByUser: false }, TOKEN_USER_B, ["unreadByUser"]),
    "user_b update user_a ticket"
  );
  const userBListAll = await runQuery({ from: [{ collectionId: "support_tickets" }] }, TOKEN_USER_B);
  expectDenied(userBListAll, "user_b list all support_tickets");
  assert.ok(
    !JSON.stringify(userBListAll.json).includes("Property admin is undefined"),
    "no undefined token.admin evaluation error"
  );
  expectDenied(await runQuery(userAListQuery, TOKEN_USER_B), "user_b list user_a support_tickets");

  // 3. Kiểm soát đồng bộ 2 chiều WriteBatch & chống giả mạo từ phía User
  // (a) Message mồ côi không cập nhật parent ticket
  expectDenied(
    await createDoc(
      `support_tickets/${ticketId}/messages`,
      "msg_orphan",
      makeSupportMsgDoc({
        messageId: "msg_orphan",
        senderId: "user_a",
        senderRole: "user",
        senderDisplayName: "User A",
        body: "Tin nhắn mồ côi",
        createdAt: now2,
      }),
      TOKEN_USER_A
    ),
    "user_a orphan message without updating parent ticket"
  );
  // (b) Cập nhật ticket không có message tương ứng trong cùng batch
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        status: "new",
        lastMessageId: "msg_missing_in_batch",
        lastMessagePreview: "Giả mạo không tạo message",
        lastMessageSenderRole: "user",
        lastMessageAt: now2,
        unreadByAdmin: true,
        unreadByUser: false,
        updatedAt: now2,
      },
      TOKEN_USER_A,
      [
        "status",
        "lastMessageId",
        "lastMessagePreview",
        "lastMessageSenderRole",
        "lastMessageAt",
        "unreadByAdmin",
        "unreadByUser",
        "updatedAt",
      ]
    ),
    "user_a update ticket without creating message in batch denied"
  );
  // (c) Tái sử dụng lastMessageId cũ (`msg_1`) khi cập nhật ticket
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        status: "new",
        lastMessageId: "msg_1",
        lastMessagePreview: "Tái sử dụng msg_1",
        lastMessageSenderRole: "user",
        lastMessageAt: now1,
        unreadByAdmin: true,
        unreadByUser: false,
        updatedAt: now2,
      },
      TOKEN_USER_A,
      [
        "status",
        "lastMessageId",
        "lastMessagePreview",
        "lastMessageSenderRole",
        "lastMessageAt",
        "unreadByAdmin",
        "unreadByUser",
        "updatedAt",
      ]
    ),
    "user_a reuse existing lastMessageId denied"
  );
  // (d) User giả mạo senderRole=admin hoặc gửi sai messageType=status_change khi nhắn thường
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_spoof_role",
            senderId: "user_a",
            senderRole: "admin",
            senderDisplayName: "Fake Admin",
            body: "Giả mạo admin",
            createdAt: now2,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "user_a spoof admin senderRole"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_wrong_type",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Sai loại message",
            messageType: "status_change",
            createdAt: now2,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "new",
          lastMessageId: "msg_wrong_type",
          lastMessagePreview: "Sai loại message",
          lastMessageSenderRole: "user",
          lastMessageAt: now2,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now2,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a mismatched messageType=status_change for regular message denied"
  );
  // (e) User tự đổi priority, tự xác nhận resolved khi ticket mới ở `new`, hoặc gửi đánh giá khi ở `new`
  expectDenied(
    await updateDoc(`support_tickets/${ticketId}`, { priority: "urgent", updatedAt: now2 }, TOKEN_USER_A, [
      "priority",
      "updatedAt",
    ]),
    "user_a change priority denied"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_user_early_resolve",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Tự xác nhận giải quyết từ new",
            messageType: "status_change",
            createdAt: now2,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "resolved",
          resolvedAt: now2,
          resolvedByRole: "user",
          lastMessageId: "msg_user_early_resolve",
          lastMessagePreview: "Tự xác nhận giải quyết từ new",
          lastMessageSenderRole: "user",
          lastMessageAt: now2,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now2,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a confirm resolved from status=new denied"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 5,
        ratingComment: "Chưa giải quyết đã đánh giá",
        ratedAt: now2,
        ratingUpdatedAt: now2,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a rate ticket while status=new denied"
  );

  // 4. Admin bị khóa / mất doc / thiếu status bị chặn; Admin hợp lệ (claim & Spark DB role) thao tác đúng quy trình
  expectDenied(await getDoc(`support_tickets/${ticketId}`, TOKEN_LOCKED_ADMIN), "locked admin denied");
  expectDenied(await getDoc(`support_tickets/${ticketId}`, TOKEN_ADMIN_DELETED_DOC), "deleted-doc admin denied");
  expectDenied(await getDoc(`support_tickets/${ticketId}`, TOKEN_ADMIN_NO_STATUS), "missing-status admin denied");
  expectDenied(
    await updateDoc(`support_tickets/${ticketId}`, { priority: "urgent", updatedAt: now2 }, TOKEN_LOCKED_ADMIN, [
      "priority",
      "updatedAt",
    ]),
    "locked admin change priority denied"
  );

  expectAllowed(await getDoc(`support_tickets/${ticketId}`, TOKEN_ADMIN), "admin read ticket");
  expectAllowed(await getDoc(`support_tickets/${ticketId}`, TOKEN_ADMIN_NO_CLAIM), "spark db-role admin read ticket");

  // Admin đánh dấu đọc & điều chỉnh mức ưu tiên (normal -> urgent)
  expectAllowed(
    await updateDoc(`support_tickets/${ticketId}`, { unreadByAdmin: false }, TOKEN_ADMIN_NO_CLAIM, ["unreadByAdmin"]),
    "admin mark read without status change"
  );
  expectAllowed(
    await updateDoc(`support_tickets/${ticketId}`, { priority: "urgent", updatedAt: now2 }, TOKEN_ADMIN_NO_CLAIM, [
      "priority",
      "updatedAt",
    ]),
    "admin adjust priority normal -> urgent"
  );

  // Admin tiếp nhận (`new` -> `in_progress`, ghi `claimedAt`) trong WriteBatch nguyên tử
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_claim",
            senderId: "admin_db",
            senderRole: "system",
            senderDisplayName: "Admin DB Role",
            body: "Admin DB Role đã tiếp nhận và bắt đầu xử lý yêu cầu.",
            messageType: "status_change",
            createdAt: now2,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          claimedAt: now2,
          lastMessageId: "msg_claim",
          lastMessagePreview: "Admin DB Role đã tiếp nhận và bắt đầu xử lý yêu cầu.",
          lastMessageSenderRole: "system",
          lastMessageAt: now2,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now2,
        }),
      ],
      TOKEN_ADMIN_NO_CLAIM
    ),
    "admin claim ticket new -> in_progress"
  );

  // Chặn Admin tiếp nhận lại (`in_progress -> in_progress`), chặn cập nhật thiếu message, chặn tái sử dụng lastMessageId, chặn sai messageType
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_reclaim",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Tiếp nhận lại sai quy trình",
            messageType: "status_change",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          lastMessageId: "msg_reclaim",
          lastMessagePreview: "Tiếp nhận lại sai quy trình",
          lastMessageSenderRole: "system",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin illegal transition in_progress -> in_progress denied"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        status: "replied",
        assignedAdminId: "admin_db",
        assignedAdminName: "Admin DB Role",
        lastMessageId: "msg_missing_admin",
        lastMessagePreview: "Không kèm message",
        lastMessageSenderRole: "admin",
        lastMessageAt: now3,
        unreadByAdmin: false,
        unreadByUser: true,
        updatedAt: now3,
      },
      TOKEN_ADMIN_NO_CLAIM,
      [
        "status",
        "assignedAdminId",
        "assignedAdminName",
        "lastMessageId",
        "lastMessagePreview",
        "lastMessageSenderRole",
        "lastMessageAt",
        "unreadByAdmin",
        "unreadByUser",
        "updatedAt",
      ]
    ),
    "admin update status without synchronized message denied"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        status: "replied",
        assignedAdminId: "admin_db",
        assignedAdminName: "Admin DB Role",
        lastMessageId: "msg_claim",
        lastMessagePreview: "Tái sử dụng msg_claim",
        lastMessageSenderRole: "system",
        lastMessageAt: now2,
        unreadByAdmin: false,
        unreadByUser: true,
        updatedAt: now3,
      },
      TOKEN_ADMIN_NO_CLAIM,
      [
        "status",
        "assignedAdminId",
        "assignedAdminName",
        "lastMessageId",
        "lastMessagePreview",
        "lastMessageSenderRole",
        "lastMessageAt",
        "unreadByAdmin",
        "unreadByUser",
        "updatedAt",
      ]
    ),
    "admin reuse existing lastMessageId denied"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_wrong_req_type",
            senderId: "admin_db",
            senderRole: "admin",
            senderDisplayName: "Admin DB Role",
            body: "Đổi sang waiting_for_user nhưng type=text",
            messageType: "text",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "waiting_for_user",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          firstAdminResponseAt: now3,
          lastMessageId: "msg_wrong_req_type",
          lastMessagePreview: "Đổi sang waiting_for_user nhưng type=text",
          lastMessageSenderRole: "admin",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN_NO_CLAIM
    ),
    "admin waiting_for_user with wrong messageType=text denied"
  );

  // Admin gửi yêu cầu bổ sung (`in_progress -> waiting_for_user`, ghi `firstAdminResponseAt`)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_req_info",
            senderId: "admin_db",
            senderRole: "admin",
            senderDisplayName: "Admin DB Role",
            body: "Bạn vui lòng chia sẻ thêm chi phí thiết yếu trung bình mỗi tháng nhé.",
            messageType: "request_info",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "waiting_for_user",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          firstAdminResponseAt: now3,
          lastMessageId: "msg_req_info",
          lastMessagePreview: "Bạn vui lòng chia sẻ thêm chi phí thiết yếu...",
          lastMessageSenderRole: "admin",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN_NO_CLAIM
    ),
    "admin atomic request_info reply"
  );

  // Không cho sửa hoặc xóa tin nhắn đã gửi
  expectDenied(
    await updateDoc(`support_tickets/${ticketId}/messages/msg_1`, { body: "Sửa lại" }, TOKEN_USER_A, ["body"]),
    "user_a edit sent message denied"
  );
  expectDenied(
    await deleteDoc(`support_tickets/${ticketId}/messages/msg_req_info`, TOKEN_ADMIN),
    "admin delete sent message denied"
  );

  // User đánh dấu đã đọc rồi gửi bổ sung (`waiting_for_user -> in_progress`)
  expectAllowed(
    await updateDoc(`support_tickets/${ticketId}`, { unreadByUser: false }, TOKEN_USER_A, ["unreadByUser"]),
    "user_a mark ticket read"
  );
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_user_reply",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Chi phí thiết yếu của tôi khoảng 8 triệu/tháng gồm nhà và ăn uống.",
            messageType: "text",
            createdAt: now4,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          lastMessageId: "msg_user_reply",
          lastMessagePreview: "Chi phí thiết yếu của tôi khoảng 8 triệu/tháng...",
          lastMessageSenderRole: "user",
          lastMessageAt: now4,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now4,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a reply auto transitions waiting_for_user -> in_progress"
  );

  // Admin gửi phản hồi tư vấn (`in_progress -> replied`), không thay đổi claimedAt/firstAdminResponseAt cũ
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_admin_reply",
            senderId: "admin_1",
            senderRole: "admin",
            senderDisplayName: "Admin 1",
            body: "Bạn nên lập ngân sách thiết yếu 8 triệu và trích tự động 3 triệu cho mục tiêu dự phòng.",
            messageType: "text",
            createdAt: now5,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "replied",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          lastMessageId: "msg_admin_reply",
          lastMessagePreview: "Bạn nên lập ngân sách thiết yếu 8 triệu...",
          lastMessageSenderRole: "admin",
          lastMessageAt: now5,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now5,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin send normal reply in_progress -> replied"
  );

  // Chặn Admin kéo ngược `replied -> in_progress` và chặn User đánh giá khi mới ở `replied`
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_back_inprog",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Kéo ngược sai quy trình",
            messageType: "status_change",
            createdAt: now6,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          lastMessageId: "msg_back_inprog",
          lastMessagePreview: "Kéo ngược sai quy trình",
          lastMessageSenderRole: "system",
          lastMessageAt: now6,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now6,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin illegal transition replied -> in_progress denied"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 5,
        ratingComment: "Đánh giá sớm ở replied",
        ratedAt: now6,
        ratingUpdatedAt: now6,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a rate ticket while status=replied denied"
  );

  // 5. User chủ động xác nhận đã giải quyết (`replied -> resolved`, `resolvedByRole: 'user'`)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_user_resolved",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "User A đã xác nhận vấn đề đã được giải quyết.",
            messageType: "status_change",
            createdAt: now6,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "resolved",
          resolvedAt: now6,
          resolvedByRole: "user",
          lastMessageId: "msg_user_resolved",
          lastMessagePreview: "User A đã xác nhận vấn đề đã được giải quyết.",
          lastMessageSenderRole: "user",
          lastMessageAt: now6,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now6,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a confirm resolved replied -> resolved"
  );

  // 6. Vòng đời đánh giá: User gửi đánh giá lần đầu ở `resolved`; chặn User B & Admin sửa; chặn Admin nhắn/đánh dấu lại ở `resolved`
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 6,
        ratingComment: "Điểm ngoài 1..5",
        ratedAt: now6,
        ratingUpdatedAt: now6,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a rating score out of range (6) denied"
  );
  expectAllowed(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 5,
        ratingComment: "Hướng dẫn rất rõ ràng và dễ áp dụng.",
        ratedAt: now6,
        ratingUpdatedAt: now6,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a submit first rating while status=resolved"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 1,
        ratingComment: "User B phá hoại",
        ratedAt: now6,
        ratingUpdatedAt: now7,
        ratingEditCount: 1,
      },
      TOKEN_USER_B,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_b edit user_a rating denied"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 5,
        ratingComment: "Admin tự sửa đánh giá",
        ratingUpdatedAt: now7,
      },
      TOKEN_ADMIN,
      ["ratingScore", "ratingComment", "ratingUpdatedAt"]
    ),
    "admin tamper with user rating denied"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_admin_on_resolved",
            senderId: "admin_1",
            senderRole: "admin",
            senderDisplayName: "Admin 1",
            body: "Admin nhắn trên ticket đã resolved",
            messageType: "text",
            createdAt: now7,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "replied",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          lastMessageId: "msg_admin_on_resolved",
          lastMessagePreview: "Admin nhắn trên ticket đã resolved",
          lastMessageSenderRole: "admin",
          lastMessageAt: now7,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now7,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin illegal transition resolved -> replied denied"
  );

  // 7. User tiếp tục nhắn tin từ `resolved -> in_progress`:
  // - Chặn nếu KHÔNG xóa resolvedAt/resolvedByRole
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_res_no_clear",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Nhắn tiếp nhưng không xóa resolvedAt",
            messageType: "text",
            createdAt: now7,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          lastMessageId: "msg_res_no_clear",
          lastMessagePreview: "Nhắn tiếp nhưng không xóa resolvedAt",
          lastMessageSenderRole: "user",
          lastMessageAt: now7,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now7,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a message from resolved -> in_progress without clearing resolvedAt denied"
  );
  // - Hợp lệ khi xóa resolvedAt & resolvedByRole (và giữ nguyên rating lịch sử!)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_res_reopen",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Mình hỏi thêm một ý nhỏ về cách gộp 2 ví tiết kiệm nhé.",
            messageType: "text",
            createdAt: now7,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          resolvedAt: null,
          resolvedByRole: null,
          lastMessageId: "msg_res_reopen",
          lastMessagePreview: "Mình hỏi thêm một ý nhỏ về cách gộp 2 ví tiết kiệm nhé.",
          lastMessageSenderRole: "user",
          lastMessageAt: now7,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now7,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a follow-up from resolved -> in_progress clears resolvedAt and keeps historical rating"
  );
  // - Trong khi quay lại `in_progress`, User KHÔNG được chỉnh sửa đánh giá lịch sử!
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 4,
        ratingComment: "Sửa khi đang in_progress",
        ratedAt: now6,
        ratingUpdatedAt: now7,
        ratingEditCount: 1,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a edit historical rating while status=in_progress denied"
  );

  // Admin đánh dấu đã giải quyết lại (`in_progress -> resolved`, `resolvedByRole: 'admin'`)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_admin_resolve2",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã đánh dấu yêu cầu là Đã giải quyết.",
            messageType: "status_change",
            createdAt: now8,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "resolved",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          resolvedAt: now8,
          resolvedByRole: "admin",
          closedAt: null,
          closeReason: null,
          lastMessageId: "msg_admin_resolve2",
          lastMessagePreview: "Admin 1 đã đánh dấu yêu cầu là Đã giải quyết.",
          lastMessageSenderRole: "system",
          lastMessageAt: now8,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now8,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin mark resolved in_progress -> resolved"
  );

  // Quay lại `resolved`: chặn sửa nếu đổi ratedAt; cho phép sửa 1 lần hợp lệ; chặn sửa lần thứ 2
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 4,
        ratingComment: "Đổi mốc ratedAt trái phép",
        ratedAt: now8,
        ratingUpdatedAt: now8,
        ratingEditCount: 1,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a edit rating tampering with ratedAt denied"
  );
  expectAllowed(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 4,
        ratingComment: "Hỗ trợ tốt, đã giải đáp thêm phần gộp ví.",
        ratingUpdatedAt: now8,
        ratingEditCount: 1,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a edit rating once when ticket returns to resolved"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 3,
        ratingComment: "Sửa lần 2 trái phép",
        ratingUpdatedAt: now9,
        ratingEditCount: 2,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a 2nd rating edit denied"
  );

  // 8. Đóng chuẩn (`resolved -> closed`):
  // - Chặn đóng chuẩn nếu ghi sai closeReason hoặc xóa/ghi đè resolvedAt
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_bad_close_reason",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Đóng sai lý do",
            messageType: "status_change",
            createdAt: now9,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "closed",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          closedAt: now9,
          closeReason: "duplicate",
          lastMessageId: "msg_bad_close_reason",
          lastMessagePreview: "Đóng sai lý do",
          lastMessageSenderRole: "system",
          lastMessageAt: now9,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now9,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin close resolved ticket with non-completed closeReason denied"
  );
  // - Đóng chuẩn hợp lệ (giữ nguyên resolvedAt & resolvedByRole, closeReason = 'completed')
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_close_std",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
            messageType: "status_change",
            createdAt: now9,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "closed",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          closedAt: now9,
          closeReason: "completed",
          lastMessageId: "msg_close_std",
          lastMessagePreview: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
          lastMessageSenderRole: "system",
          lastMessageAt: now9,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now9,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin standard close resolved -> closed"
  );

  // Kiểm chứng thêm trên 1 ticket đã do User xác nhận resolved nhưng chưa đánh giá:
  // - Admin không được ghi đè resolvedByRole='user' -> 'admin' khi đóng chuẩn
  // - Sau khi đóng chuẩn mà chưa đánh giá, User bị chặn gửi đánh giá lần đầu trên ticket đã closed
  const userResTicketId = "sup_user_res_unrated";
  await seedDoc(`support_tickets/${userResTicketId}`, {
    ...makeSupportTicketDoc({
      ticketId: userResTicketId,
      ticketCode: "SUP-261119-UR01",
      now: now1,
    }),
    status: "resolved",
    assignedAdminId: "admin_1",
    assignedAdminName: "Admin 1",
    resolvedAt: now6,
    resolvedByRole: "user",
    lastMessageId: "msg_ur_res",
    lastMessagePreview: "User A đã xác nhận vấn đề đã được giải quyết.",
    lastMessageSenderRole: "user",
    lastMessageAt: now6,
    updatedAt: now6,
  });
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          userResTicketId,
          makeSupportMsgDoc({
            messageId: "msg_ur_bad_close",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Đóng ghi đè resolvedByRole",
            messageType: "status_change",
            createdAt: now9,
          })
        ),
        ticketPatchWrite(userResTicketId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          resolvedByRole: "admin",
          closedAt: now9,
          closeReason: "completed",
          lastMessageId: "msg_ur_bad_close",
          lastMessagePreview: "Đóng ghi đè resolvedByRole",
          lastMessageSenderRole: "system",
          lastMessageAt: now9,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now9,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin overwrite resolvedByRole=user to admin on close denied"
  );
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          userResTicketId,
          makeSupportMsgDoc({
            messageId: "msg_ur_good_close",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
            messageType: "status_change",
            createdAt: now9,
          })
        ),
        ticketPatchWrite(userResTicketId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          closedAt: now9,
          closeReason: "completed",
          lastMessageId: "msg_ur_good_close",
          lastMessagePreview: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
          lastMessageSenderRole: "system",
          lastMessageAt: now9,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now9,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin close user-resolved ticket preserving resolvedByRole=user"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${userResTicketId}`,
      {
        ratingScore: 5,
        ratingComment: "Gửi đánh giá lần đầu sau khi đã đóng",
        ratedAt: now10,
        ratingUpdatedAt: now10,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a blocked from submitting first rating after standard close"
  );

  // 9. Khi đã `closed`: chặn toàn bộ nhắn tin, mở lại, đổi ưu tiên, đánh giá/sửa đánh giá
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_closed_user",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Thử nhắn vào ticket đã đóng",
            messageType: "text",
            createdAt: now10,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          lastMessageId: "msg_closed_user",
          lastMessagePreview: "Thử nhắn vào ticket đã đóng",
          lastMessageSenderRole: "user",
          lastMessageAt: now10,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: now10,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a blocked from messaging closed ticket"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_closed_admin_reply",
            senderId: "admin_1",
            senderRole: "admin",
            senderDisplayName: "Admin 1",
            body: "Admin nhắn vào ticket đã đóng",
            messageType: "text",
            createdAt: now10,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "replied",
          assignedAdminId: "admin_db",
          assignedAdminName: "Admin DB Role",
          lastMessageId: "msg_closed_admin_reply",
          lastMessagePreview: "Admin nhắn vào ticket đã đóng",
          lastMessageSenderRole: "admin",
          lastMessageAt: now10,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now10,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin blocked from replying on closed ticket"
  );
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          ticketId,
          makeSupportMsgDoc({
            messageId: "msg_closed_reopen",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Mở lại ticket đã đóng trái phép",
            messageType: "status_change",
            createdAt: now10,
          })
        ),
        ticketPatchWrite(ticketId, {
          status: "in_progress",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          closedAt: null,
          closeReason: null,
          lastMessageId: "msg_closed_reopen",
          lastMessagePreview: "Mở lại ticket đã đóng trái phép",
          lastMessageSenderRole: "system",
          lastMessageAt: now10,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now10,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin blocked from reopening closed ticket"
  );
  expectDenied(
    await updateDoc(`support_tickets/${ticketId}`, { priority: "low", updatedAt: now10 }, TOKEN_ADMIN, [
      "priority",
      "updatedAt",
    ]),
    "admin blocked from changing priority on closed ticket"
  );
  expectDenied(
    await updateDoc(
      `support_tickets/${ticketId}`,
      {
        ratingScore: 5,
        ratingComment: "Sửa sau khi đã đóng",
        ratingUpdatedAt: now10,
        ratingEditCount: 1,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a blocked from editing rating on closed ticket"
  );
});

test("Support Center (Spark): Đóng ngoại lệ chưa giải quyết, tham chiếu ticket đã đóng & khóa bảo vệ hệ thống", async () => {
  const now1 = "2026-11-20T08:00:00.000Z";
  const now2 = "2026-11-20T08:10:00.000Z";
  const now3 = "2026-11-20T08:20:00.000Z";
  const now4 = "2026-11-20T08:30:00.000Z";

  // 1. Tạo ticket cho luồng đóng ngoại lệ chưa giải quyết (`in_progress -> closed`)
  const excId = "sup_ticket_exc1";
  const excTicket = makeSupportTicketDoc({
    ticketId: excId,
    ticketCode: "SUP-261120-EX01",
    category: "other",
    title: "Yêu cầu trùng lặp cần đóng ngoại lệ",
    description: "Nội dung trùng với yêu cầu trước đó mà tôi đã gửi hôm qua.",
    now: now1,
  });
  expectAllowed(
    await commitWrites(
      [
        {
          update: { name: docName(`support_tickets/${excId}`), ...toFirestoreDoc(excTicket) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          excId,
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: excTicket.description,
            createdAt: now1,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "create ticket for unresolved close flow"
  );

  // Admin tiếp nhận (`new -> in_progress`)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          excId,
          makeSupportMsgDoc({
            messageId: "msg_claim",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã tiếp nhận và bắt đầu xử lý yêu cầu.",
            messageType: "status_change",
            createdAt: now2,
          })
        ),
        ticketPatchWrite(excId, {
          status: "in_progress",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          claimedAt: now2,
          lastMessageId: "msg_claim",
          lastMessagePreview: "Admin 1 đã tiếp nhận và bắt đầu xử lý yêu cầu.",
          lastMessageSenderRole: "system",
          lastMessageAt: now2,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now2,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin claim exc ticket"
  );

  // Chặn đóng trực tiếp từ `in_progress` nếu cố ghi `resolvedAt != null` hoặc `resolvedByRole = 'admin'` hoặc `closeReason = 'completed'`
  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          excId,
          makeSupportMsgDoc({
            messageId: "msg_bad_close1",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Đóng giả giải quyết",
            messageType: "status_change",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(excId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          resolvedAt: now3,
          resolvedByRole: "admin",
          closedAt: now3,
          closeReason: "completed",
          lastMessageId: "msg_bad_close1",
          lastMessagePreview: "Đóng giả giải quyết",
          lastMessageSenderRole: "system",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin direct close in_progress -> closed with fake resolvedAt/completed denied"
  );

  expectDenied(
    await commitWrites(
      [
        msgCreateWrite(
          excId,
          makeSupportMsgDoc({
            messageId: "msg_bad_close2",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Đóng thiếu lý do ngoại lệ",
            messageType: "status_change",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(excId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          resolvedAt: null,
          resolvedByRole: null,
          closedAt: now3,
          closeReason: null,
          lastMessageId: "msg_bad_close2",
          lastMessagePreview: "Đóng thiếu lý do ngoại lệ",
          lastMessageSenderRole: "system",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin unresolved close without valid closeReason denied"
  );

  // Đóng ngoại lệ hợp lệ: `resolvedAt == null`, `resolvedByRole == null`, `closeReason == 'duplicate'`
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          excId,
          makeSupportMsgDoc({
            messageId: "msg_close_exc",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã đóng yêu cầu (chưa giải quyết). Lý do: Trùng lặp yêu cầu đã có.",
            messageType: "status_change",
            createdAt: now3,
          })
        ),
        ticketPatchWrite(excId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          resolvedAt: null,
          resolvedByRole: null,
          closedAt: now3,
          closeReason: "duplicate",
          lastMessageId: "msg_close_exc",
          lastMessagePreview: "Admin 1 đã đóng yêu cầu (chưa giải quyết).",
          lastMessageSenderRole: "system",
          lastMessageAt: now3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: now3,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin valid unresolved exception close with resolvedAt=null"
  );

  // User không thể đánh giá ticket đóng ngoại lệ chưa giải quyết (hoặc bất kỳ ticket đã closed nào)
  expectDenied(
    await updateDoc(
      `support_tickets/${excId}`,
      {
        ratingScore: 1,
        ratingComment: "Thử đánh giá ticket đã đóng chưa giải quyết",
        ratedAt: now4,
        ratingUpdatedAt: now4,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a blocked from rating unresolved closed ticket"
  );

  // 2. Tạo ticket mới có tham chiếu ticket đã đóng:
  // - Hợp lệ khi tham chiếu ticket đã `closed` thuộc chính User A với đúng `ticketCode`
  const followUpId = "sup_ticket_followup1";
  const followUpTicket = makeSupportTicketDoc({
    ticketId: followUpId,
    ticketCode: "SUP-261120-FU01",
    category: "financial_advisory",
    title: "Phát sinh lại câu hỏi sau khi đóng yêu cầu cũ",
    description: "Tôi gặp thêm câu hỏi mới liên quan tới yêu cầu trước đã đóng.",
    now: now4,
    extra: {
      relatedTicketId: excId,
      relatedTicketCode: "SUP-261120-EX01",
    },
  });
  expectAllowed(
    await commitWrites(
      [
        {
          update: { name: docName(`support_tickets/${followUpId}`), ...toFirestoreDoc(followUpTicket) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          followUpId,
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: followUpTicket.description,
            createdAt: now4,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "user_a create new ticket referencing own closed ticket"
  );

  // - Chặn User B tham chiếu ticket đã đóng của User A
  const spoofRefUserB = makeSupportTicketDoc({
    ticketId: "sup_spoof_ref_b",
    ticketCode: "SUP-261120-SB01",
    userId: "user_b",
    userName: "User B",
    userEmail: "user_b@staging.test",
    now: now4,
    extra: {
      relatedTicketId: excId,
      relatedTicketCode: "SUP-261120-EX01",
    },
  });
  expectDenied(
    await commitWrites(
      [
        {
          update: { name: docName("support_tickets/sup_spoof_ref_b"), ...toFirestoreDoc(spoofRefUserB) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          "sup_spoof_ref_b",
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_b",
            senderRole: "user",
            senderDisplayName: "User B",
            body: spoofRefUserB.description,
            createdAt: now4,
          })
        ),
      ],
      TOKEN_USER_B
    ),
    "user_b referencing user_a closed ticket denied"
  );

  // - Chặn User A tham chiếu ticket CHƯA đóng (`sup_ticket_bug1` đang `new`)
  const refOpenTicket = makeSupportTicketDoc({
    ticketId: "sup_ref_open",
    ticketCode: "SUP-261120-RO01",
    now: now4,
    extra: {
      relatedTicketId: "sup_ticket_bug1",
      relatedTicketCode: "SUP-261119-BG01",
    },
  });
  expectDenied(
    await commitWrites(
      [
        {
          update: { name: docName("support_tickets/sup_ref_open"), ...toFirestoreDoc(refOpenTicket) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          "sup_ref_open",
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: refOpenTicket.description,
            createdAt: now4,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "user_a referencing non-closed ticket denied"
  );

  // - Chặn User A giả mạo mã `relatedTicketCode` không khớp
  const refBadCode = makeSupportTicketDoc({
    ticketId: "sup_ref_badcode",
    ticketCode: "SUP-261120-BC01",
    now: now4,
    extra: {
      relatedTicketId: excId,
      relatedTicketCode: "SUP-FAKE-9999",
    },
  });
  expectDenied(
    await commitWrites(
      [
        {
          update: { name: docName("support_tickets/sup_ref_badcode"), ...toFirestoreDoc(refBadCode) },
          currentDocument: { exists: false },
        },
        msgCreateWrite(
          "sup_ref_badcode",
          makeSupportMsgDoc({
            messageId: "msg_1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: refBadCode.description,
            createdAt: now4,
          })
        ),
      ],
      TOKEN_USER_A
    ),
    "user_a referencing own closed ticket with wrong ticketCode denied"
  );

  // 3. Khóa bảo vệ hiện hữu: internal_notes, notifications, admin_logs và dữ liệu tài chính cá nhân
  await seedDoc(`support_tickets/${excId}/internal_notes/note_1`, {
    noteId: "note_1",
    adminId: "admin_1",
    content: "Ghi chú nội bộ",
    createdAt: now3,
  });
  expectDenied(
    await getDoc(`support_tickets/${excId}/internal_notes/note_1`, TOKEN_USER_A),
    "user_a read internal_notes denied"
  );
  expectDenied(
    await getDoc(`support_tickets/${excId}/internal_notes/note_1`, TOKEN_ADMIN),
    "admin client read internal_notes still locked"
  );
  expectDenied(
    await createDoc(
      `support_tickets/${excId}/internal_notes`,
      "note_2",
      { noteId: "note_2", content: "hack" },
      TOKEN_USER_A
    ),
    "user_a write internal_notes denied"
  );
  expectDenied(
    await createDoc(
      "notifications",
      "notif_admin_spoof",
      {
        userId: "user_a",
        title: "Test",
        content: "Admin không được ghi thẳng notifications",
        type: "reminder",
        status: "unread",
        createdAt: now4,
      },
      TOKEN_ADMIN
    ),
    "admin direct create user notification remains denied"
  );
  expectDenied(
    await createDoc(
      "admin_logs",
      "log_admin_spoof",
      {
        action: "support_close",
        adminId: "admin_1",
        createdAt: now4,
      },
      TOKEN_ADMIN
    ),
    "admin direct client write to admin_logs remains denied"
  );
  await seedDoc("wallets/wallet_private_check", {
    userId: "user_a",
    name: "Ví tiền mặt",
    balance: 5000000,
  });
  expectDenied(
    await getDoc("wallets/wallet_private_check", TOKEN_ADMIN),
    "admin read user private wallet remains denied"
  );
});

test("Support Center (Spark): Tương thích ngược với ticket cũ (legacy) thiếu toàn bộ trường dữ liệu mới", async () => {
  const legacyActiveId = "sup_legacy_active";
  const legacyResolvedId = "sup_legacy_resolved";
  const t1 = "2026-10-01T09:00:00.000Z";
  const t2 = "2026-10-01T10:00:00.000Z";
  const t3 = "2026-10-01T11:00:00.000Z";
  const t4 = "2026-10-01T12:00:00.000Z";

  // Seed ticket kiểu cũ MVP (KHÔNG có lastMessageId, priority, userImpact, technicalInfo, claimedAt, resolvedByRole, closeReason, rating*)
  await seedDoc(`support_tickets/${legacyActiveId}`, {
    ticketId: legacyActiveId,
    ticketCode: "SUP-261001-LEG1",
    userId: "user_a",
    userName: "User A",
    userEmail: "user_a@staging.test",
    category: "app_guide",
    title: "Ticket kiểu cũ đang ở replied",
    description: "Ticket tạo trước khi có các trường mới của giai đoạn cải tiến.",
    status: "replied",
    assignedAdminId: "admin_1",
    assignedAdminName: "Admin 1",
    lastMessagePreview: "Phản hồi cũ từ Admin",
    lastMessageSenderRole: "admin",
    lastMessageAt: t1,
    unreadByAdmin: false,
    unreadByUser: true,
    createdAt: t1,
    updatedAt: t1,
    resolvedAt: null,
    closedAt: null,
  });

  // 1. User đọc & đánh dấu đã đọc ticket cũ
  expectAllowed(await getDoc(`support_tickets/${legacyActiveId}`, TOKEN_USER_A), "user_a read legacy ticket");
  expectAllowed(
    await updateDoc(`support_tickets/${legacyActiveId}`, { unreadByUser: false }, TOKEN_USER_A, ["unreadByUser"]),
    "user_a mark legacy ticket read"
  );

  // 2. Admin điều chỉnh mức ưu tiên cho ticket cũ
  expectAllowed(
    await updateDoc(`support_tickets/${legacyActiveId}`, { priority: "high", updatedAt: t2 }, TOKEN_ADMIN, [
      "priority",
      "updatedAt",
    ]),
    "admin adjust priority on legacy ticket"
  );

  // 3. User nhắn tiếp trên ticket cũ (`replied -> in_progress`, bổ sung lastMessageId đồng bộ)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          legacyActiveId,
          makeSupportMsgDoc({
            messageId: "msg_leg_u1",
            senderId: "user_a",
            senderRole: "user",
            senderDisplayName: "User A",
            body: "Mình đã thử và muốn xác nhận thêm bước cuối.",
            createdAt: t2,
          })
        ),
        ticketPatchWrite(legacyActiveId, {
          status: "in_progress",
          lastMessageId: "msg_leg_u1",
          lastMessagePreview: "Mình đã thử và muốn xác nhận thêm bước cuối.",
          lastMessageSenderRole: "user",
          lastMessageAt: t2,
          unreadByAdmin: true,
          unreadByUser: false,
          updatedAt: t2,
        }),
      ],
      TOKEN_USER_A
    ),
    "user_a send message on legacy ticket upgrades cleanly"
  );

  // 4. Admin phản hồi lại ticket cũ (`in_progress -> replied`, ghi bổ sung claimedAt/firstAdminResponseAt)
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          legacyActiveId,
          makeSupportMsgDoc({
            messageId: "msg_leg_a1",
            senderId: "admin_1",
            senderRole: "admin",
            senderDisplayName: "Admin 1",
            body: "Bạn chỉ cần nhấn Lưu là hoàn tất nhé.",
            createdAt: t3,
          })
        ),
        ticketPatchWrite(legacyActiveId, {
          status: "replied",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          claimedAt: t3,
          firstAdminResponseAt: t3,
          lastMessageId: "msg_leg_a1",
          lastMessagePreview: "Bạn chỉ cần nhấn Lưu là hoàn tất nhé.",
          lastMessageSenderRole: "admin",
          lastMessageAt: t3,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: t3,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin reply on legacy ticket"
  );

  // 5. Seed ticket kiểu cũ đã ở `resolved` (có resolvedAt nhưng KHÔNG có resolvedByRole, lastMessageId, rating*)
  await seedDoc(`support_tickets/${legacyResolvedId}`, {
    ticketId: legacyResolvedId,
    ticketCode: "SUP-261001-LEG2",
    userId: "user_a",
    userName: "User A",
    userEmail: "user_a@staging.test",
    category: "other",
    title: "Ticket kiểu cũ đã resolved",
    description: "Ticket đã giải quyết từ trước khi nâng cấp.",
    status: "resolved",
    assignedAdminId: "admin_1",
    assignedAdminName: "Admin 1",
    lastMessagePreview: "Admin 1 đã đánh dấu Đã giải quyết.",
    lastMessageSenderRole: "system",
    lastMessageAt: t1,
    unreadByAdmin: false,
    unreadByUser: false,
    createdAt: t1,
    updatedAt: t1,
    resolvedAt: t1,
    closedAt: null,
  });

  // User gửi đánh giá trên ticket cũ đã `resolved`
  expectAllowed(
    await updateDoc(
      `support_tickets/${legacyResolvedId}`,
      {
        ratingScore: 5,
        ratingComment: "Đánh giá trên ticket kiểu cũ.",
        ratedAt: t3,
        ratingUpdatedAt: t3,
        ratingEditCount: 0,
      },
      TOKEN_USER_A,
      ["ratingScore", "ratingComment", "ratedAt", "ratingUpdatedAt", "ratingEditCount"]
    ),
    "user_a rate legacy resolved ticket"
  );

  // Admin đóng chuẩn ticket cũ `resolved -> closed` (bảo toàn resolvedAt, điền resolvedByRole='admin', closeReason='completed')
  expectAllowed(
    await commitWrites(
      [
        msgCreateWrite(
          legacyResolvedId,
          makeSupportMsgDoc({
            messageId: "msg_leg_close",
            senderId: "admin_1",
            senderRole: "system",
            senderDisplayName: "Admin 1",
            body: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
            messageType: "status_change",
            createdAt: t4,
          })
        ),
        ticketPatchWrite(legacyResolvedId, {
          status: "closed",
          assignedAdminId: "admin_1",
          assignedAdminName: "Admin 1",
          resolvedByRole: "admin",
          closedAt: t4,
          closeReason: "completed",
          lastMessageId: "msg_leg_close",
          lastMessagePreview: "Admin 1 đã đóng yêu cầu hỗ trợ sau khi giải quyết.",
          lastMessageSenderRole: "system",
          lastMessageAt: t4,
          unreadByAdmin: false,
          unreadByUser: true,
          updatedAt: t4,
        }),
      ],
      TOKEN_ADMIN
    ),
    "admin standard close on legacy resolved ticket"
  );
});
