# HƯỚNG DẪN CẤU HÌNH & DEPLOY CLOUD FUNCTIONS GỬI MÃ OTP QUA GMAIL

Hệ thống này cung cấp backend bảo mật cho chức năng:
**Gửi mã OTP 6 số qua Email $\rightarrow$ Nhập 6 ô mã trên ứng dụng $\rightarrow$ Đặt lại mật khẩu mới trực tiếp trong ứng dụng.**

---

## 1. Chuẩn bị Mật khẩu ứng dụng Gmail (Gmail App Password)

Để Cloud Functions có thể gửi email từ tài khoản Gmail của bạn mà không bị Google chặn bảo mật:

1. Mở trang quản lý tài khoản Google: [https://myaccount.google.com/security](https://myaccount.google.com/security)
2. Bật tính năng **Xác minh 2 bước (2-Step Verification)** (nếu chưa bật).
3. Vào ô tìm kiếm của trang Tài khoản Google, gõ tìm: **"Mật khẩu ứng dụng" (App passwords)**.
4. Đặt tên ứng dụng là `Finance AI App` và nhấn **Tạo (Create)**.
5. Google sẽ cấp cho bạn một chuỗi mật khẩu 16 chữ cái (dạng `abcd efgh ijkl mnop`). Hãy lưu lại chuỗi này!

---

## 2. Điền thông tin vào `functions/index.js` hoặc cấu hình Firebase

### Cách 1 (Nhanh nhất): Điền trực tiếp vào biến môi trường trong file
Mở file `functions/index.js`, tìm dòng 12-13 và thay bằng Gmail + App Password của bạn:
```javascript
const EMAIL_USER = "emailcuaban@gmail.com";
const EMAIL_PASS = "abcdefghijklmnop"; // 16 ký tự mật khẩu ứng dụng
```

### Cách 2 (Khuyến nghị chuẩn Production):
Chạy lệnh trong terminal:
```bash
firebase functions:config:set email.user="emailcuaban@gmail.com" email.pass="abcdefghijklmnop"
```

---

## 3. Cài đặt thư viện và Deploy lên Firebase

Mở Terminal tại thư mục gốc của dự án:

```bash
# 1. Chuyển vào thư mục functions và cài đặt thư viện
cd functions
npm install

# 2. Deploy các hàm lên Firebase (yêu cầu Firebase CLI)
firebase deploy --only functions
```

Sau khi deploy hoàn tất, Firebase CLI sẽ xuất ra 3 đường link HTTPS:
- `https://us-central1-finance-ai-app-6df28.cloudfunctions.net/sendPasswordResetOtp`
- `https://us-central1-finance-ai-app-6df28.cloudfunctions.net/verifyOtp`
- `https://us-central1-finance-ai-app-6df28.cloudfunctions.net/resetPasswordWithOtp`

---

## 4. Chế độ Kiểm thử tức thì trong Ứng dụng (Dev Mock Mode)

Trong lúc bạn chưa kịp deploy Cloud Functions lên Google Cloud:
- Ứng dụng Flutter đã được tích hợp sẵn cơ chế **Tự phát hiện môi trường**.
- Khi chạy ở chế độ Debug (`flutter run`), nếu máy chủ chưa online, app sẽ tự động sinh mã OTP thử nghiệm: **`123456`**.
- Bạn có thể nhập mã `123456` vào 6 ô OTP trên ứng dụng để trải nghiệm toàn bộ luồng đổi mật khẩu mượt mà ngay trên máy!
