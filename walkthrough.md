# Walkthrough: Xác nhận giao dịch định kỳ trước khi hạch toán tiền thật

Đã hoàn thành nâng cấp tính năng **Giao dịch định kỳ & Hóa đơn** cho `finance_ai_app`. Người dùng hiện có thể kiểm soát linh hoạt việc hạch toán tiền thật thông qua chế độ **Yêu cầu xác nhận** (`manualConfirmation`) hoặc **Tự động ghi nhận** (`autoPost`).

---

## 1. Danh sách file tạo mới và chỉnh sửa

### File tạo mới:
- [`lib/models/recurring_transaction_occurrence_model.dart`](file:///d:/finance_ai_app/lib/models/recurring_transaction_occurrence_model.dart): Model audit log cho collection Firestore `recurringTransactionOccurrences/{scheduleId}_{occurrenceKey}`.

### File chỉnh sửa:
- [`lib/models/recurring_transaction_model.dart`](file:///d:/finance_ai_app/lib/models/recurring_transaction_model.dart): Bổ sung trường `postingMode` với 2 giá trị `manualConfirmation` (mặc định cho lịch mới) và `autoPost` (fallback cho lịch cũ).
- [`firestore.rules`](file:///d:/finance_ai_app/firestore.rules): Security Rules cho `recurringTransactionOccurrences` — tách riêng `read` (cho phép `resource == null` để hỗ trợ get-or-create) và `delete` (bắt buộc `resource.data.userId` match, không dùng `resource == null`).
- [`lib/services/firestore_service.dart`](file:///d:/finance_ai_app/lib/services/firestore_service.dart):
  - Lọc `processDueRecurringTransactions()` chỉ tự động xử lý các lịch `autoPost`.
  - Bổ sung `confirmRecurringOccurrence()`, `skipRecurringOccurrence()`, `deferRecurringOccurrence()`, và `streamRecurringOccurrences()`.
  - Cả 3 hàm thủ công đều **đọc occurrence audit document bên trong Firestore Transaction** — nếu đã tồn tại thì throw Exception, không cập nhật `nextDueDate` thêm lần nữa.
- [`lib/services/local_notification_service.dart`](file:///d:/finance_ai_app/lib/services/local_notification_service.dart): Cập nhật tiêu đề/nội dung nhắc nhở khi đến hạn/sắp đến hạn cho chế độ `manualConfirmation` ("Hôm nay cần xác nhận: ...").
- [`lib/screens/management/recurring_transaction_screen.dart`](file:///d:/finance_ai_app/lib/screens/management/recurring_transaction_screen.dart):
  - Thêm khu vực ưu tiên **Cần xác nhận hôm nay** ở đầu màn hình.
  - Bổ sung 3 nút hành động: `[Xác nhận đã nhận/thanh toán]`, `[Bỏ qua kỳ này]`, `[Dời ngày]`.
  - **UI button locking**: Dùng `Set<String> _actionInProgressIds` theo `scheduleId` để disable toàn bộ nút hành động trong lúc request đang chạy, chống double-tap. Hiện spinner trên nút confirm đang xử lý.
  - Cập nhật Form tạo/sửa lịch với tùy chọn Radio `Cách ghi nhận giao dịch`.
- [`test/recurring_transaction_service_test.dart`](file:///d:/finance_ai_app/test/recurring_transaction_service_test.dart) & [`test/local_notification_service_test.dart`](file:///d:/finance_ai_app/test/local_notification_service_test.dart): Bổ sung 14 kịch bản kiểm thử mới (test #18–#31), bao gồm 4 test edge-case bắt buộc cuối cùng.

---

## 2. Chi tiết các luồng xử lý bắt buộc

### A. Luồng Xác nhận (`confirmRecurringOccurrence`)
1. Hiện dialog xác nhận gồm tên lịch, số tiền, ví hạch toán và ngày hạch toán (`nextDueDate`).
2. Chạy **Firestore Transaction atomic**:
   - Kiểm tra occurrence document `${scheduleId}_${occurrenceKey}` hoặc transaction document `recurring_${scheduleId}_${occurrenceKey}` xem đã tồn tại chưa (chống thao tác trùng).
   - Kiểm tra số dư ví (nếu khoản chi) và trạng thái hoạt động của ví.
   - Tạo transaction thật `AppTransaction` với ID xác định (`recurring_${scheduleId}_${occurrenceKey}`).
   - Cập nhật số dư ví theo thu/chi (`FieldValue.increment`).
   - Cập nhật `nextDueDate` trên schedule sang kỳ lặp kế tiếp.
   - Tạo document audit `recurringTransactionOccurrences/${scheduleId}_${occurrenceKey}` với `action: 'confirmed'` và `transactionId`.

### B. Luồng Bỏ qua kỳ này (`skipRecurringOccurrence`)
1. Hiện dialog xác nhận bỏ qua kỳ hiện tại.
2. UI khóa tất cả nút hành động cho `scheduleId` đang xử lý (chống double-tap).
3. Chạy **Firestore Transaction atomic**:
   - **Đọc occurrence audit document** `${scheduleId}_${occurrenceKey}` — nếu đã tồn tại → throw Exception, không cập nhật `nextDueDate`.
   - Không tạo document trong `transactions`.
   - Không làm thay đổi số dư ví.
   - Cập nhật `nextDueDate` trên schedule sang kỳ lặp kế tiếp.
   - Tạo document audit `recurringTransactionOccurrences/${scheduleId}_${occurrenceKey}` với `action: 'skipped'`.
4. UI mở khóa nút (cả khi thành công hay thất bại, qua `finally`).

### C. Luồng Dời ngày (`deferRecurringOccurrence`)
1. Mở `DatePicker`, chỉ cho chọn ngày từ hôm nay trở đi (`firstDate: DateTime.now()`).
2. Giải thích rõ trên UI: *"Các kỳ sau sẽ được tính tiếp từ ngày đã dời."*
3. UI khóa tất cả nút hành động cho `scheduleId` đang xử lý.
4. Chạy **Firestore Transaction atomic**:
   - **Đọc occurrence audit document** `${scheduleId}_${occurrenceKey}` — nếu đã tồn tại → throw Exception, không ghi đè `nextDueDate`.
   - Không tạo transaction và không làm thay đổi số dư ví.
   - Cập nhật `nextDueDate` trên schedule thành ngày mới đã dời.
   - Tạo document audit `recurringTransactionOccurrences/${scheduleId}_${occurrenceKey}` với `action: 'deferred'` và `deferredTo`.
5. UI mở khóa nút (qua `finally`).

---

## 3. Rules Firestore mới cần Publish

Cần Publish block rule sau lên **Firebase Console -> Firestore Database -> Rules**:

```firestore
    match /recurringTransactionOccurrences/{occurrenceId} {
      allow read: if request.auth != null
        && (resource == null || request.auth.uid == resource.data.userId);

      allow delete: if request.auth != null
        && request.auth.uid == resource.data.userId;

      allow create: if request.auth != null
        && request.auth.uid == request.resource.data.userId;

      allow update: if request.auth != null
        && request.auth.uid == resource.data.userId
        && request.resource.data.userId == resource.data.userId
        && request.resource.data.userId == request.auth.uid;
    }
```

> **Thay đổi so với phiên bản trước**: Tách `read` và `delete` thành 2 rule riêng biệt. `delete` không dùng `resource == null` — chỉ xóa được khi document đã tồn tại và thuộc về user.

---

## 4. Kết quả kiểm thử & git diff stat

### Kết quả `flutter analyze`:
```text
211 issues found.
  - 0 errors
  - 3 warnings (tất cả là unused_import có sẵn, KHÔNG thuộc file đã chỉnh sửa)
  - 208 infos (chủ yếu deprecated_member_use với withOpacity, prefer_const_constructors, use_super_parameters)
```

### Kết quả `flutter test`:
```text
00:04 +103: All tests passed!
```
*Tổng cộng **103 tests** (31 kịch bản recurring + 11 intelligence + 9 business logic + 6 formatter + 46 notification/forecast/export) — tất cả pass 100%.*

### 4 test edge-case bổ sung cuối (tests 28–31):
| # | Kịch bản | Kỳ vọng |
|---|----------|--------|
| 28 | Skip cùng occurrence 2 lần | Lần 2 throw, `nextDueDate` chỉ tiến 1 kỳ |
| 29 | Defer cùng occurrence 2 lần | Lần 2 throw, `nextDueDate` giữ `deferredDate1` |
| 30 | Confirm sau skip | Bị reject, không tạo transaction |
| 31 | Confirm sau defer | Bị reject, không tạo transaction |

### Thống kê `git diff --stat`:
```text
 firestore.rules                                    |  16 +
 lib/models/recurring_transaction_model.dart        |   9 +
 .../recurring_transaction_occurrence_model.dart    |  58 ++ (NEW FILE)
 .../management/recurring_transaction_screen.dart   | 595 ++++++++++++++++++++-
 lib/services/firestore_service.dart                | 211 ++++++++
 lib/services/local_notification_service.dart       |  14 +-
 test/local_notification_service_test.dart          |   1 +
 test/recurring_transaction_service_test.dart       | 714 +++++++++++++++++++++
 walkthrough.md                                     | 221 +++----
 9 files changed, 1682 insertions(+), 157 deletions(-)
```

---

## 5. Hướng dẫn thử nghiệm thực tế trên Android

1. **Khởi chạy ứng dụng**:
   ```bash
   flutter run -d android
   ```
2. **Thêm lịch định kỳ cần xác nhận**:
   - Vào mục **Cài đặt / Hồ sơ** -> **Giao dịch định kỳ & Hóa đơn**.
   - Bấm **Thêm lịch mới**.
   - Nhập tên khoản: *"Tiền điện"* (1,000,000đ), chọn ví.
   - Tại phần **Cách ghi nhận giao dịch**, chọn **Cần xác nhận khi đến hạn**.
   - Chọn ngày bắt đầu là **hôm nay**.
   - Bấm **Lưu lịch định kỳ**.

3. **Kiểm tra giao diện & thao tác**:
   - Mục **Cần xác nhận hôm nay** xuất hiện ở trên cùng màn hình.
   - Khoản *"Tiền điện"* hiển thị kèm 3 nút: `[Xác nhận thanh toán]`, `[Bỏ qua kỳ này]`, `[Dời ngày]`.
   - **Thử Xác nhận**: Bấm nút -> Xem dialog chi tiết -> Đồng ý xác nhận -> Kiểm tra số dư ví giảm 1,000,000đ và giao dịch mới xuất hiện trong Sổ thu chi.
   - **Thử Bỏ qua / Dời ngày**: Tạo lịch thử nghiệm khác -> Thử bỏ qua hoặc chọn dời ngày sang tuần sau -> Kiểm tra số dư ví giữ nguyên và lịch nhảy `nextDueDate`.

---

## 6. Xác nhận tính an toàn của Notification

- **Xác nhận**: Việc thiết bị nhận hoặc người dùng chạm vào thông báo nhắc nhở (`LocalNotificationService`) **KHÔNG tự động xác nhận, KHÔNG tạo transaction và KHÔNG làm thay đổi số dư ví**.
- Notification chỉ mang tính chất nhắc nhở người dùng và khi chạm vào notification sẽ điều hướng an toàn tới màn hình **Giao dịch định kỳ & Hóa đơn** để chờ người dùng chủ động bấm xác nhận.
