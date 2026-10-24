const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// ----------------------------------------------------------------------
// CẤU HÌNH GỬI EMAIL (GMAIL SMTP HOẶC DỊCH VỤ EMAIL TÙY CHỌN)
// Bạn có thể cấu hình qua Firebase Environment Config hoặc điền thông tin:
// firebase functions:config:set email.user="your-email@gmail.com" email.pass="your-app-password"
// ----------------------------------------------------------------------
const EMAIL_USER = process.env.EMAIL_USER || functions.config().email?.user || "nguyenduongquoc9a11@gmail.com";
const rawPass = process.env.EMAIL_PASS || functions.config().email?.pass || "bhyl ziku afbz kffp";
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
