/**
 * Script khởi tạo dữ liệu mẫu & tài khoản Admin kiểm thử trong Firebase Emulators cục bộ
 * (Auth Emulator + Firestore Emulator).
 *
 * Yêu cầu biến môi trường khi chạy:
 *   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *
 * Cách dùng:
 *   node functions/scripts/seed_emulator.js --email <admin_email> --password <admin_password>
 */
const admin = require("../node_modules/firebase-admin");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token.startsWith("--")) {
      const key = token.slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : "true";
      args[key] = val;
      if (val !== "true") i += 1;
    }
  }
  return args;
}

async function ensureAuthUser({ auth, email, password, displayName, claims }) {
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    await auth.updateUser(userRecord.uid, {
      password,
      displayName,
      disabled: false,
      emailVerified: true,
    });
  } catch (_) {
    userRecord = await auth.createUser({
      email,
      password,
      displayName,
      disabled: false,
      emailVerified: true,
    });
  }
  await auth.setCustomUserClaims(userRecord.uid, claims || {});
  return userRecord;
}

async function main() {
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      "Cần chạy với FIREBASE_AUTH_EMULATOR_HOST và FIRESTORE_EMULATOR_HOST trỏ vào Emulator cục bộ."
    );
  }

  const args = parseArgs(process.argv.slice(2));
  const projectId = args.project || process.env.GCLOUD_PROJECT || "finance-ai-app-6df28";
  const adminEmail = (args.email || process.env.SEED_ADMIN_EMAIL || "admin@local.test")
    .trim()
    .toLowerCase();
  const adminPassword = args.password || process.env.SEED_ADMIN_PASSWORD || "Admin@123456";
  const userEmail = (args.userEmail || "user@local.test").trim().toLowerCase();
  const userPassword = args.userPassword || "User@123456";

  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }

  const auth = admin.auth();
  const db = admin.firestore();
  const nowIso = new Date().toISOString();

  // 1. Tài khoản Admin kiểm thử (Custom Claim admin=true + hồ sơ users/{uid} active)
  const adminRecord = await ensureAuthUser({
    auth,
    email: adminEmail,
    password: adminPassword,
    displayName: "Quản trị viên Hệ thống (Local Emulator)",
    claims: { admin: true },
  });

  await db.collection("users").doc(adminRecord.uid).set({
    uid: adminRecord.uid,
    name: "Quản trị viên Hệ thống",
    email: adminEmail,
    role: "admin",
    status: "active",
    occupation: "System Admin",
    createdAt: nowIso,
    updatedAt: nowIso,
  });

  // 2. Tài khoản User mẫu để đối chiếu phân quyền & danh sách Platform Ops
  const sampleUserRecord = await ensureAuthUser({
    auth,
    email: userEmail,
    password: userPassword,
    displayName: "Người dùng Kiểm thử",
    claims: {},
  });

  await db.collection("users").doc(sampleUserRecord.uid).set({
    uid: sampleUserRecord.uid,
    name: "Người dùng Kiểm thử",
    email: userEmail,
    role: "user",
    status: "active",
    occupation: "Nhân viên văn phòng",
    createdAt: nowIso,
    updatedAt: nowIso,
  });

  // 3. Seed System Categories, Announcements & Audit Log mẫu
  await db.collection("system_categories").doc("sys_cat_an_uong").set(
    {
      id: "sys_cat_an_uong",
      name: "Ăn uống",
      type: "expense",
      icon: "restaurant",
      color: 4294934528,
      isActive: true,
      createdAt: nowIso,
    },
    { merge: true }
  );

  await db.collection("system_announcements").doc("ann_welcome_local").set(
    {
      id: "ann_welcome_local",
      title: "Môi trường Emulator Kiểm thử Admin Web",
      content: "Hệ thống đang chạy trên Firebase Emulators cục bộ (Auth + Firestore + Functions).",
      level: "info",
      isActive: true,
      createdAt: nowIso,
    },
    { merge: true }
  );

  await db.collection("admin_logs").doc("log_emulator_seed").set(
    {
      adminId: adminRecord.uid,
      adminEmail,
      action: "SEED_LOCAL_EMULATOR",
      targetType: "system",
      targetId: projectId,
      targetLabel: "Local Emulator Bootstrap",
      result: "success",
      details: "Khởi tạo dữ liệu mẫu & tài khoản Admin kiểm thử trong Emulator cục bộ.",
      source: "emulator_seed",
      createdAt: nowIso,
    },
    { merge: true }
  );

  console.log(
    JSON.stringify({
      seeded: true,
      projectId,
      adminUid: adminRecord.uid,
      adminEmail,
      sampleUserUid: sampleUserRecord.uid,
      sampleUserEmail: userEmail,
    })
  );
}

main().catch((err) => {
  console.error("Seed emulator thất bại:", err);
  process.exit(1);
});
