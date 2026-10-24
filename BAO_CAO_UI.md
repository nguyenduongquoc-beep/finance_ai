# BÁO CÁO TOÀN DIỆN KIỂM TRA (AUDIT) GIAO DIỆN & CÔNG NGHỆ UI
## DỰ ÁN: FINANCE AI APP (FINAI)

> **Ngày thực hiện:** 17/10/2026  
> **Người thực hiện:** Senior Flutter Developer & UI/UX Architect  
> **Trạng thái mã nguồn:** Đã kiểm tra toàn bộ thư mục `lib/` (Không chỉnh sửa mã nguồn trong đợt audit này)

---

## MỤC LỤC
1. [Tổng quan Định vị Ứng dụng & Giải đáp các tính năng đặc biệt](#1-tổng-quan-định-vị-ứng-dụng--giải-đáp-các-tính-năng-đặc-biệt)
2. [Hệ sinh thái Công nghệ Giao diện (UI/UX Tech Stack)](#2-hệ-sinh-thái-công-nghệ-giao-diện-uiux-tech-stack)
3. [Kiến trúc Điều hướng & Phân bổ Màn hình](#3-kiến-trúc-điều-hướng--phân-bổ-màn-hình)
4. [Bảng Kiểm tra Chi tiết Toàn bộ 28 Màn hình (Data & Interactions)](#4-bảng-kiểm-tra-chi-tiết-toàn-bộ-28-màn-hình-data--interactions)
   - [4.1. Nhóm Điều hướng Chính & Dashboard (5 màn hình)](#41-nhóm-điều-hướng-chính--dashboard)
   - [4.2. Nhóm Trí tuệ Nhân tạo AI (3 màn hình)](#42-nhóm-trí-tuệ-nhân-tạo-ai)
   - [4.3. Nhóm Quản trị Tài chính & Kế hoạch (6 màn hình)](#43-nhóm-quản-trị-tài-chính--kế-hoạch)
   - [4.4. Nhóm Xác thực Tài khoản & Onboarding (7 màn hình)](#44-nhóm-xác-thực-tài-khoản--onboarding)
   - [4.5. Nhóm Thiết lập Ban đầu - Setup Wizard (3 màn hình)](#45-nhóm-thiết-lập-ban-đầu---setup-wizard)
   - [4.6. Nhóm Hồ sơ Cá nhân, Bảo mật & Cài đặt (4 màn hình)](#46-nhóm-hồ-sơ-cá-nhân-bảo-mật--cài-đặt)
5. [Danh mục Thư viện Component & Widget Dùng chung (18 Widgets)](#5-danh-mục-thư-viện-component--widget-dùng-chung-18-widgets)
6. [Đánh giá UI/UX & Khuyến nghị Lộ trình Nâng cấp](#6-đánh-giá-uiux--khuyến-nghị-lộ-trình-nâng-cấp)

---

## 1. TỔNG QUAN ĐỊNH VỊ ỨNG DỤNG & GIẢI ĐÁP CÁC TÍNH NĂNG ĐẶC BIỆT

Ứng dụng **Finance AI App** được kiến trúc là một hệ thống **Quản lý Tài chính Cá nhân Thông minh kết hợp Cố vấn AI (Personal Finance & AI Financial Advisor)** chuẩn Fintech.

Để làm rõ ngay các chức năng mà người dùng quan tâm qua câu hỏi khảo sát:

| Chức năng người dùng đề cập | Trạng thái thực tế trong dự án | Vị trí màn hình / Triển khai kỹ thuật |
| :--- | :---: | :--- |
| **Phần quét hóa đơn (Scan hóa đơn / biên lai)** | **ĐÃ CÓ (RẤT MẠNH)** | Nằm tại `AddTransactionScreen` và nút Quick Action trên `HomeDashboardScreen`. Sử dụng **Google ML Kit Text Recognition** qua camera/thư viện ảnh để tự động trích xuất: số tiền tổng, tên đơn vị bán hàng, ngày thanh toán và gợi ý phân loại danh mục. |
| **Lên lịch định kỳ (Lịch hóa đơn & thanh toán)** | **ĐÃ CÓ (HOÀN CHỈNH)** | Nằm tại `RecurringTransactionScreen`. Cho phép lên lịch thu/chi lặp lại (Hàng ngày, Hàng tuần, Hàng tháng, Hàng năm), thiết lập thời hạn, nhắc nhở thông báo trước hạn, tự động ghi nhận giao dịch định kỳ (Auto-post) hoặc xác nhận thủ công (Xác nhận, Bỏ qua, Hoãn lại). |
| **Bảng kết quả Kiểm tra Sức khỏe Tài chính (Check-up)** | **ĐÃ CÓ (CHUYÊN SÂU)** | Nằm tại `AiInsightScreen`. Cung cấp điểm sức khỏe tài chính (Health Score 0-100), phân tích điểm mạnh/yếu, chẩn đoán vấn đề 4 bước (Vấn đề → Nguyên nhân → Hệ quả → Giải pháp), phân bổ ngân sách 50/30/20, tỷ lệ giữ tiền, tính khả thi mục tiêu tiết kiệm, và kế hoạch hành động cụ thể cho tháng tới. |
| **Phân tích video / Biểu đồ nến để Trade (Chứng khoán / Crypto)** | **CHƯA CÓ / KHÔNG THUỘC PHẠM VI** | Dự án tập trung vào **Quản lý dòng tiền cá nhân (Thu - Chi - Tiết kiệm - Ngân sách)**, không phải là sàn giao dịch hay bot trading chứng khoán/crypto. Biểu đồ trong app hiện tại là **biểu đồ dòng tiền thu chi (Cashflow Bar Chart / Line Chart)** và **biểu đồ phân bổ chi tiêu tròn (Pie Chart)** qua thư viện `fl_chart`. |

---

## 2. HỆ SINH THÁI CÔNG NGHỆ GIAO DIỆN (UI/UX TECH STACK)

Dự án áp dụng ngôn ngữ thiết kế **Modern Flat Neutral Fintech Design System** kết hợp các công nghệ Flutter hiện đại:

| Thành phần | Thư viện / Công nghệ | Vai trò & Mục đích sử dụng |
| :--- | :--- | :--- |
| **Core Framework** | Flutter SDK (>=3.3.0 <4.0.0) | Nền tảng xây dựng UI đa nền tảng di động (Android & iOS). |
| **State & Reactive** | `provider` + `StreamBuilder` | Quản lý trạng thái giao diện real-time, phản ứng tức thì với dữ liệu Cloud Firestore mà không gây lag giật. |
| **Biểu đồ & Thị giác hóa** | `fl_chart: ^0.69.0` | Vẽ biểu đồ cột thu nhập - chi phí so sánh 6 tháng, biểu đồ đường số dư luỹ kế, biểu đồ tròn phân bổ danh mục. |
| **Chỉ số tiến độ trực quan** | `percent_indicator: ^4.2.3` | Thanh tiến độ ngân sách danh mục, tiến độ tích luỹ mục tiêu tiết kiệm. |
| **Custom Canvas / Heatmap** | `CustomPainter` thuần Flutter | Vẽ biểu đồ nhiệt nhịp độ chi tiêu hàng tuần (`WeeklyHeatmapCard`) dạng lưới đóng góp phong cách GitHub. |
| **Bàn phím nhập số Fintech** | Custom `NumpadWidget` | Bộ bàn phím số xúc giác chuyên biệt cho tài chính (nút 000, phím xoá lùi, phím hoàn tất, tính toán nhẩm). |
| **Thị giác máy tính (OCR)** | `google_mlkit_text_recognition: ^0.16.0` | Nhận diện văn bản hóa đơn trực tiếp trên thiết bị (On-device OCR) bảo mật cao, không cần gửi ảnh lên server. |
| **Typography & Font chữ** | `google_fonts: ^6.2.1` (Inter) | Bộ font chữ chuẩn quốc tế Inter, cấu hình số liệu dạng `FontFeature.tabularFigures()` giúp các cột số tiền không bị lệch hàng. |
| **Generative AI** | `google_generative_ai: ^0.4.6` (Gemini API) | Trợ lý tài chính AI đàm thoại tự nhiên, phân tích chuyên sâu báo cáo tài chính và chẩn đoán chi tiêu bất thường. |
| **Xuất báo cáo & In ấn** | `pdf: ^3.11.1`, `printing: ^5.13.2`, `share_plus: ^10.1.4` | Tạo tài liệu báo cáo tài chính dạng PDF, xem trước và chia sẻ/in ấn qua khay hệ thống. |
| **Thông báo cục bộ** | `flutter_local_notifications: ^17.2.3` | Lên lịch nhắc nhở thanh toán hóa đơn đến hạn và cảnh báo vượt ngưỡng ngân sách. |
| **Theme System** | Dual Theme (Light & Dark Mode) | Hỗ trợ chuyển đổi giao diện sáng/tối tự động với hệ thống Semantic Colors: Petrol `#1F6F8B`, Income `#2E8B57`, Expense `#C0453A`. |

---

## 3. KIẾN TRÚC ĐIỀU HƯỚNG & PHÂN BỔ MÀN HÌNH

Hệ thống điều hướng chính của FinAI sử dụng cấu trúc **Bottom Navigation 5 Tab** tại `MainNavigation`:

```
┌────────────────────────────────────────────────────────────────────────┐
│                          MAIN NAVIGATION (5 TABS)                      │
├──────────────┬──────────────┬──────────────┬──────────────┬────────────┤
│    Tab 1     │    Tab 2     │    Tab 3     │    Tab 4     │   Tab 5    │
│  [Tổng quan] │ [Sổ giao dịch│  [Thêm (+)]  │ [Trợ lý AI]  │ [Cá nhân]  │
│  Home Dash   │   Tx List    │  Add Screen  │   AI Chat    │  Profile   │
└──────────────┴──────────────┴──────────────┴──────────────┴────────────┘
```

Tổng cộng dự án có **28 màn hình giao diện (Screens)** được tổ chức theo 6 nhóm chức năng chuyên biệt:

```
lib/screens/
├── home/                 (4 màn hình: Dashboard, Add Tx + OCR, Tx List, Tx Detail)
├── ai/                   (3 màn hình: AI Chat, AI Financial Insights, AI PDF Report)
├── management/           (6 màn hình: Wallets, Categories, Budget Overview, Budget Setup, Saving Goals, Recurring Tx)
├── auth/                 (7 màn hình: Splash, Onboarding, Login, Register, Forgot Password, OTP Verify, Reset Password)
├── setup/                (3 màn hình: Profile Setup, Wallet Setup, Category Setup)
└── (root)/               (5 màn hình: Profile Screen, Personal Info, Account Security, Notifications, About App)
```

---

## 4. BẢNG KIỂM TRA CHI TIẾT TOÀN BỘ 28 MÀN HÌNH (DATA & INTERACTIONS)

### 4.1. Nhóm Điều hướng Chính & Dashboard

#### 1. Màn hình Tổng quan (`home_dashboard_screen.dart`)
- **Dữ liệu hiển thị:**
  - Header: Lời chào cá nhân hóa theo buổi (Sáng/Chiều/Tối), họ tên người dùng, avatar và chuông thông báo (kèm chấm đỏ khi có tin mới).
  - Thẻ Số dư Tổng (Balance Hero Card): Tổng tài sản ròng từ các ví đang kích hoạt, nút ẩn/hiện số dư (`•••••••• ₫`), rút gọn số tiền thông minh (`Tr`, `Tỷ`) kèm thanh tỷ lệ Thu / Chi trong tháng.
  - Thao tác nhanh (Quick Actions Bar): 4 nút tròn nổi bật:
    1. *Thu nhập:* Mở nhanh form ghi nhận thu tiền.
    2. *Chuyển tiền:* Mở nhanh giao dịch luân chuyển giữa 2 ví.
    3. *Quét hóa đơn (OCR):* Kích hoạt ngay camera/thư viện ảnh để quét hoá đơn tự động.
    4. *Báo cáo AI:* Mở màn hình xuất báo cáo tài chính PDF.
  - Tổng quan tháng (Monthly Overview): Doanh số Thu, Chi, Dòng tiền ròng (Net Cashflow) và tổng số lượng giao dịch đã phát sinh.
  - Xu hướng tài chính (Trend Panel): Bộ chọn năm & kỳ 6 tháng (Kỳ 1 / Kỳ 2), thanh trượt chọn tháng, Biểu đồ cột so sánh Thu - Chi (`fl_chart`).
  - Cơ cấu danh mục (Category Panel): Biểu đồ tròn cơ cấu chi tiêu / nguồn thu (`fl_chart`), danh sách top danh mục kèm % và số tiền.
  - Giao dịch gần đây (Recent Transactions): 4 giao dịch mới nhất kèm icon danh mục, tên ví, ngày giờ và số tiền đổi màu (xanh/đỏ). Nút "Xem toàn bộ X giao dịch".
  - Banner Trợ lý AI (AI Callout): Thẻ mời kiểm tra sức khỏe tài chính định kỳ.
- **Nút bấm & Tương tác:**
  - Nút con mắt: Bật/tắt chế độ riêng tư ẩn số dư.
  - Nút Avatar / Chuông: Chuyển đến màn hình Thông báo (`NotificationScreen`).
  - 4 nút Quick Actions (Thu, Chuyển, Quét OCR, Báo cáo AI).
  - Dropdown chọn Năm, Tab Kỳ 1/Kỳ 2, Tab cuộn Tháng.
  - Toggle Thu / Chi tại bảng cơ cấu danh mục.
  - Chạm vào thẻ giao dịch: Chuyển sang màn hình chi tiết (`TransactionDetailScreen`).
  - Vuốt xuống (Pull-to-refresh) để làm mới toàn bộ dữ liệu.

#### 2. Màn hình Thêm / Chỉnh sửa Giao dịch (`add_transaction_screen.dart`)
- **Dữ liệu hiển thị:**
  - Bộ chọn Loại giao dịch: 5 phân loại chuẩn Fintech: *Chi phí*, *Thu nhập*, *Chuyển khoản*, *Đi vay*, *Cho vay*.
  - Khung nhập số tiền siêu lớn: Hiển thị định dạng tiền tệ thời gian thực (ví dụ `150.000 ₫`).
  - Nút Quét OCR Hóa đơn: Kèm huy hiệu `AI OCR`.
  - Bộ chọn Ví tiền: Tên ví nguồn, số dư khả dụng hiện tại (và ví đích nếu là chuyển khoản).
  - Bộ chọn Danh mục: Icon màu sắc, tên danh mục, thanh tìm kiếm danh mục.
  - Thẻ Gợi ý Danh mục AI (AI Category Suggestion): Tự động phân tích nội dung ghi chú để gợi ý danh mục phù hợp.
  - Cảnh báo Bất thường (Anomaly Alert): Hệ thống phát hiện chi tiêu bất thường nếu số tiền vượt mức chi tiêu trung bình lịch sử của danh mục này.
  - Trạng thái Ngân sách: Tính toán tức thì giao dịch này sẽ chiếm bao nhiêu % hạn mức ngân sách tháng của danh mục đó (Bình thường / Sắp chạm hạn mức / Vượt ngân sách).
  - Chip Gợi ý Mẫu nhanh (Quick Templates): Các chip 1 chạm (Ăn trưa, Cà phê, Xăng xe, Đi chợ...).
  - Trường Ngày & Giờ: Mặc định hiện tại, có nút chọn nhanh "Hôm nay", "Hôm qua".
  - Trường Ghi chú & Địa điểm giao dịch.
  - Bàn phím số Numpad cảm ứng xúc giác.
- **Nút bấm & Tương tác:**
  - Nút chụp ảnh từ Máy ảnh / Chọn ảnh từ Thư viện để kích hoạt nhận diện OCR Google ML Kit.
  - Bàn phím Numpad: Các phím 0-9, nút `000`, nút xoá `⌫`, nút Done.
  - Modal chọn Ví tiền và Modal chọn Danh mục với ô tìm kiếm tức thì.
  - Nút "Lưu giao dịch" (kèm trạng thái loading spinner ngăn bấm đúp).

#### 3. Màn hình Sổ Giao dịch (`transaction_list_screen.dart`)
- **Dữ liệu hiển thị:**
  - Thanh tìm kiếm thông minh: Hỗ trợ gõ tiếng Việt không dấu, tìm theo số tiền tắt (`50k`, `1.5tr`), tìm theo thời gian tự nhiên (`hôm nay`, `tháng trước`).
  - Thẻ Tóm tắt Dòng tiền: Tổng thu, tổng chi và chênh lệch ròng của tập giao dịch đang được lọc.
  - Danh sách giao dịch gom nhóm theo Ngày (Grouped by Date): Mỗi nhóm ngày có tổng chi tiêu trong ngày.
  - Các thẻ giao dịch đầy đủ thông tin: Danh mục, ví sử dụng, ghi chú, giờ thực hiện, số tiền.
- **Nút bấm & Tương tác:**
  - Ô tìm kiếm text.
  - Nút Bộ lọc nâng cao (Filter Bottom Sheet): Lọc theo Khoảng ngày (Date Range), theo Danh mục, theo Ví, theo Loại giao dịch (Thu/Chi/Chuyển), theo Khoảng số tiền (Min - Max).
  - Nút Xuất file CSV: Tạo và chia sẻ tệp dữ liệu giao dịch bảng tính.
  - Vuốt ngang trên từng dòng giao dịch (Dismissible/Actions): Sửa nhanh hoặc Xoá giao dịch.
  - Nhấp vào giao dịch: Xem chi tiết.

#### 4. Màn hình Chi tiết Giao dịch (`transaction_detail_screen.dart`)
- **Dữ liệu hiển thị:**
  - Huy hiệu loại giao dịch, số tiền lớn nổi bật (+ xanh lá cho thu, - đỏ cho chi).
  - Hàng thông tin chi tiết: Danh mục (icon + tên), Ví thực hiện, Ngày giờ chính xác, Địa điểm, Ghi chú chi tiết.
  - Hình ảnh hóa đơn đính kèm (nếu có): Thumbnail ảnh chụp thực tế.
- **Nút bấm & Tương tác:**
  - Chạm vào ảnh hóa đơn: Mở popup phóng to ảnh toàn màn hình (Interactive Zoom).
  - Nút Sửa (Edit): Điều hướng sang `AddTransactionScreen` với toàn bộ dữ liệu điền sẵn.
  - Nút Xoá (Delete): Mở hộp thoại xác nhận xoá, hoàn lại số dư ví tương ứng và đóng màn hình.

---

### 4.2. Nhóm Trí tuệ Nhân tạo AI

#### 5. Màn hình Trợ lý AI Đàm thoại (`ai/ai_chat_screen.dart`)
- **Dữ liệu hiển thị:**
  - Giao diện chat song phương chuẩn quốc tế giữa Người dùng và FinAI Assistant.
  - Các thẻ tin nhắn hỗ trợ định dạng Markdown (tiêu đề, in đậm, danh sách gạch đầu dòng, bảng số liệu).
  - Bối cảnh tài chính tự động (Context Injection): FinAI tự động hiểu số dư hiện tại, tổng chi tiêu tháng, ngân sách đang có để tư vấn thực tế mà người dùng không cần gõ lại.
  - Chip gợi ý câu hỏi thông minh (Dynamic Prompt Chips): Ví dụ: "Tháng này tôi tiêu nhiều vào đâu?", "Làm sao để tiết kiệm 3 triệu tháng tới?", "Đánh giá ngân sách ăn uống của tôi".
  - Trạng thái phản hồi của AI (Typing indicator animation).
- **Nút bấm & Tương tác:**
  - Khung nhập tin nhắn tự co giãn theo độ dài.
  - Nút Gửi tin nhắn (Send button).
  - Nút xoá lịch sử hội thoại (Clear chat).
  - Chạm vào các Prompt Chips để gửi nhanh câu hỏi mẫu.

#### 6. Màn hình Phân tích Chuyên sâu & Sức khỏe Tài chính (`ai/ai_insight_screen.dart`)
*(Đây chính là nơi chứa "Bảng kết quả Check-up" mà người dùng quan tâm)*
- **Dữ liệu hiển thị:**
  1. *Bảng Điểm Sức khỏe Tài chính (Financial Health Score):* Thước đo điểm từ 0 đến 100 với vòng tròn tiến độ, xếp loại (Xuất sắc / Tốt / Cần cải thiện / Báo động) và tóm tắt Điểm mạnh & Điểm yếu.
  2. *Chẩn đoán Vấn đề 4 bước (Issue Diagnosis):* Phân tích rõ: Vấn đề phát hiện → Nguyên nhân gốc rễ → Mức độ tác động tài chính → Giải pháp hành động đề xuất.
  3. *Phân tích Dòng tiền & Tỷ lệ Giữ tiền (Retention Rate):* Tỷ lệ % thu nhập giữ lại được sau khi trừ chi phí.
  4. *Mô hình Ngân sách 50/30/20:* So sánh cơ cấu chi tiêu thực tế của người dùng với chuẩn mực tài chính (Thiết yếu 50% - Linh hoạt 30% - Tiết kiệm/Đầu tư 20%).
  5. *Đánh giá Tính khả thi Mục tiêu Tiết kiệm:* Phân tích tốc độ tiết kiệm hiện tại có kịp hạn chót của các quỹ mục tiêu hay không.
  6. *Kế hoạch Hành động Tháng tới (Action Plan):* Các đầu mối công việc cụ thể để cắt giảm chi phí không cần thiết.
  7. *Nhịp độ Chi tiêu Tuần (Spending Rhythm Heatmap):* Biểu đồ ma trận nhiệt các ngày trong tuần và các tuần trong tháng để nhận diện ngày thường "vung tay quá trán".
  8. *Dự báo Dòng tiền & Số dư Tương lai:* Đồ thị dự báo số dư ví đến cuối tháng dựa trên tốc độ tiêu dùng hàng ngày.
  9. *Nhận xét chuyên sâu từ Gemini AI:* Bản phân tích tổng quan do AI tổng hợp từ toàn bộ dữ liệu tài chính người dùng.
- **Nút bấm & Tương tác:**
  - Nút "Phân tích lại / Làm mới": Chạy lại thuật toán kiểm tra sức khỏe tài chính.
  - Nút kích hoạt tư vấn sâu từ Gemini AI: Gửi yêu cầu giải thích chi tiết.
  - Chạm vào từng thẻ vấn đề để mở rộng xem nguyên nhân và hành động đề xuất.

#### 7. Màn hình Báo cáo Tài chính AI (`ai/ai_report_screen.dart`)
- **Dữ liệu hiển thị:**
  - Bộ chọn kỳ báo cáo: Tháng này, Tháng trước, Quý này, hoặc Năm nay.
  - Khung xem trước tài liệu PDF trực tiếp (PDF Preview Engine): Báo cáo gồm bìa thiết kế đẹp mắt, bảng tổng kết thu chi, biểu đồ danh mục, phân tích sức khỏe và khuyến nghị của AI.
- **Nút bấm & Tương tác:**
  - Nút Đổi kỳ báo cáo.
  - Nút Xuất PDF / In ấn: Kết nối với máy in hoặc xuất ra file `.pdf` lưu vào bộ nhớ máy.
  - Nút Chia sẻ (Share Plus): Gửi file báo cáo qua Email, Zalo, Google Drive, Telegram...

---

### 4.3. Nhóm Quản trị Tài chính & Kế hoạch

#### 8. Màn hình Quản lý Ví tiền (`management/wallet_management_screen.dart`)
- **Dữ liệu hiển thị:**
  - Thẻ Tổng Tài sản ròng: Tổng số dư cộng dồn của tất cả các ví đang hoạt động.
  - Danh sách ví tiền: Phân loại theo Tiền mặt, Thẻ ngân hàng, Thẻ tín dụng, Ví điện tử, Sổ tiết kiệm.
  - Thông tin mỗi ví: Tên ví, số dư, 4 số cuối tài khoản/thẻ, màu sắc định danh, công tắc bật/tắt kích hoạt (Active switch).
- **Nút bấm & Tương tác:**
  - Nút Floating Action Button (+) "Thêm ví mới".
  - Chạm vào thẻ ví để Sửa tên, đổi màu, điều chỉnh số dư ban đầu hoặc xoá ví.
  - Công tắc (Switch) bật/tắt ví: Nếu tắt, số dư ví sẽ không được tính vào tổng tài sản ròng.

#### 9. Màn hình Quản lý Danh mục Thu - Chi (`management/category_management_screen.dart`)
- **Dữ liệu hiển thị:**
  - Hai Tab chuyển đổi: Tab "Chi phí" (Expense) và Tab "Thu nhập" (Income).
  - Lưới danh mục: Hiển thị icon trực quan, màu nền nhận diện, tên danh mục và số lượng giao dịch đã ghi nhận theo danh mục này.
- **Nút bấm & Tương tác:**
  - Nút (+) "Thêm danh mục".
  - Modal tạo/sửa danh mục: Chọn biểu tượng từ kho Icon, chọn bảng màu, nhập tên danh mục, chọn danh mục cha (nếu là danh mục con).
  - Vuốt hoặc chạm để chỉnh sửa / xoá danh mục tùy chỉnh.

#### 10. Màn hình Tổng quan Ngân sách (`management/budget_management_screen.dart`)
- **Dữ liệu hiển thị:**
  - Thanh chọn Tháng/Năm xem ngân sách.
  - Thẻ Tổng quan Ngân sách: Tổng ngân sách đặt ra, Tổng tiền đã chi tiêu, Số tiền còn lại được tiêu, Tỷ lệ phần trăm đã dùng.
  - Thước đo cảnh báo trực quan: Đổi màu xanh (<80%), vàng (80-100%), đỏ (vượt quá 100%).
  - Danh sách ngân sách theo từng danh mục: Thanh tiến độ chi tiết của từng khoản (Ăn uống, Mua sắm, Di chuyển...) kèm số ngày còn lại trong tháng và mức chi tiêu an toàn khuyến nghị mỗi ngày.
- **Nút bấm & Tương tác:**
  - Nút chọn Tháng / Năm.
  - Nút "Thiết lập ngân sách": Mở màn hình cài đặt ngân sách (`budget_setup_screen.dart`).
  - Chạm vào từng ngân sách để điều chỉnh hạn mức.

#### 11. Màn hình Thiết lập Ngân sách (`management/budget_setup_screen.dart`)
- **Dữ liệu hiển thị:**
  - Chọn tháng áp dụng ngân sách.
  - Danh sách toàn bộ các danh mục chi tiêu với trường nhập số tiền hạn mức mong muốn cho từng danh mục.
  - Tổng số tiền ngân sách ước tính cộng dồn ở chân trang.
- **Nút bấm & Tương tác:**
  - Các ô nhập tiền hạn mức cho từng danh mục (kèm nút sao chép hạn mức từ tháng trước).
  - Nút "Lưu thiết lập ngân sách".

#### 12. Màn hình Mục tiêu Tiết kiệm (`management/saving_goal_screen.dart`)
- **Dữ liệu hiển thị:**
  - Tổng số tiền đã tích luỹ trên toàn bộ các mục tiêu.
  - Danh sách các mục tiêu tiết kiệm (ví dụ: Quỹ khẩn cấp, Mua xe mới, Du lịch Đà Nẵng, Học chứng chỉ...):
    - Tên mục tiêu, ảnh đại diện/icon.
    - Số tiền hiện có / Số tiền mục tiêu.
    - Thanh tiến độ % hoàn thành.
    - Hạn chót (Deadline) và số ngày còn lại.
    - Ví chỉ định dùng để giữ tiền tiết kiệm.
- **Nút bấm & Tương tác:**
  - Nút (+) "Tạo mục tiêu tiết kiệm mới".
  - Nút "Nạp tiền vào quỹ" (Deposit): Trừ tiền từ ví chi tiêu chuyển vào quỹ tiết kiệm.
  - Nút "Rút tiền từ quỹ" (Withdraw): Chuyển tiền từ quỹ về lại ví chi tiêu.
  - Sửa hoặc xoá mục tiêu tiết kiệm.

#### 13. Màn hình Giao dịch Định kỳ & Lịch Hóa đơn (`management/recurring_transaction_screen.dart`)
*(Đây chính là màn hình "Lên lịch định kỳ & Quản lý lịch thanh toán" của dự án)*
- **Dữ liệu hiển thị:**
  - Thẻ Tổng quan: Số lượng khoản định kỳ đang kích hoạt, tổng số tiền sắp đến hạn trong chu kỳ tới.
  - Bộ lọc khoảng ngày sắp tới: 7 ngày, 14 ngày, hoặc 30 ngày tới.
  - Danh sách các kỳ đến hạn (Upcoming Due Occurrences): Hiển thị tên khoản chi, số tiền, ngày đến hạn chính xác, ví thanh toán và trạng thái (Chờ xác nhận / Đã thanh toán / Bị hoãn).
  - Danh sách các Quy tắc định kỳ (Active Schedules): Tần suất lặp lại (Hàng ngày, Hàng tuần, Hàng tháng, Hàng năm), chế độ Auto-post (tự động tạo giao dịch khi tới hạn hay nhắc nhở người dùng duyệt).
- **Nút bấm & Tương tác:**
  - Thao tác nhanh trên từng kỳ đến hạn:
    - *Nút "Xác nhận ngay" (Confirm & Post):* Ghi nhận tức thì thành giao dịch thực tế và trừ tiền trong ví.
    - *Nút "Bỏ qua kỳ này" (Skip):* Không ghi nhận kỳ này, chuyển sang kỳ tiếp theo.
    - *Nút "Hoãn lại" (Defer):* Dời hạn thanh toán sang ngày khác.
  - Nút (+) "Thêm lịch định kỳ mới": Form nhập tên, số tiền, danh mục, ví nguồn, tần suất lặp, ngày bắt đầu, ngày kết thúc và cấu hình thông báo nhắc nhở.
  - Nút "Kiểm tra ngay giao dịch đến hạn" (Run Due Processing): Kích hoạt thủ công tiến trình quét các khoản đến hạn.

---

### 4.4. Nhóm Xác thực Tài khoản & Onboarding

#### 14. Màn hình Khởi động (`auth/splash_screen.dart`)
- **Dữ liệu & Tương tác:**
  - Logo FinAI với hiệu ứng Fade-in mượt mà, tên ứng dụng và slogan.
  - Tự động kiểm tra trạng thái phiên làm việc (Firebase Auth session):
    - Nếu đã đăng nhập và đủ hồ sơ: Chuyển thẳng vào `MainNavigation` (Dashboard).
    - Nếu chưa thiết lập hồ sơ: Chuyển vào Setup Wizard.
    - Nếu chưa đăng nhập: Chuyển vào `OnboardingScreen` hoặc `LoginScreen`.

#### 15. Màn hình Giới thiệu (`auth/onboarding_screen.dart`)
- **Dữ liệu hiển thị:**
  - Băng chuyền 3 slide giới thiệu tính năng vượt trội của FinAI:
    1. Quản lý dòng tiền thông minh & Chống thâm hụt ngân sách.
    2. Quét hóa đơn tự động tức thì bằng Trí tuệ nhân tạo (AI OCR).
    3. Cố vấn tài chính cá nhân 24/7 với Gemini AI.
  - Chỉ số chấm trang (Page indicator dots).
- **Nút bấm & Tương tác:**
  - Vuốt ngang để đổi slide.
  - Nút "Bỏ qua" (Skip): Chuyển nhanh đến Đăng nhập.
  - Nút "Bắt đầu ngay" (Get Started): Mở màn hình Đăng ký / Đăng nhập.

#### 16. Màn hình Đăng nhập (`auth/login_screen.dart`)
- **Dữ liệu hiển thị:**
  - Tiêu đề chào mừng, ô nhập Email, ô nhập Mật khẩu (kèm icon ẩn/hiện mật khẩu).
  - Trạng thái kiểm tra lỗi validation tức thì.
  - Nút "Quên mật khẩu?".
  - Đường kẻ phân cách "Hoặc tiếp tục với".
  - Nút Đăng nhập bằng Google (Google Sign-In).
  - Dòng liên kết "Chưa có tài khoản? Đăng ký ngay".
- **Nút bấm & Tương tác:**
  - Nhập dữ liệu, nút mắt xem mật khẩu.
  - Nút "Đăng nhập" (có loading spinner chống double click).
  - Nút Google Sign-In với popup xác thực của Google.
  - Chuyển hướng sang Đăng ký hoặc Quên mật khẩu.

#### 17. Màn hình Đăng ký Tài khoản (`auth/register_screen.dart`)
- **Dữ liệu hiển thị:**
  - Ô nhập Họ và tên, Email, Mật khẩu, Xác nhận mật khẩu.
  - Thước đo Độ mạnh Mật khẩu (Password Strength Meter): 4 vạch màu trực quan (Yếu - Trung bình - Khá - Rất mạnh) kèm gợi ý ký tự hoa, số, ký tự đặc biệt.
  - Hộp kiểm (Checkbox) đồng ý với Điều khoản dịch vụ và Chính sách bảo mật.
  - Nút Đăng ký bằng Google.
- **Nút bấm & Tương tác:**
  - Tương tác nhập liệu, checkbox điều khoản.
  - Nút "Tạo tài khoản" (gọi Firebase Auth để tạo người dùng và khởi tạo hồ sơ Firestore).
  - Nút chuyển về Đăng nhập.

#### 18. Màn hình Quên Mật khẩu (`auth/forgot_password_screen.dart`)
- **Dữ liệu hiển thị:**
  - Minh họa ổ khóa bảo mật, đoạn văn bản hướng dẫn gửi mã xác minh 6 số về hòm thư.
  - Ô nhập địa chỉ Email đăng ký tài khoản.
  - Trạng thái phản hồi lỗi (Email không tồn tại, sai cú pháp).
- **Nút bấm & Tương tác:**
  - Nút "Gửi mã xác nhận": Gửi email chứa mã OTP 6 chữ số qua Firebase Cloud Functions / Nodemailer.
  - Tự động điều hướng sang màn hình nhập OTP (`OtpVerificationScreen`).

#### 19. Màn hình Xác minh OTP (`auth/otp_verification_screen.dart`)
- **Dữ liệu hiển thị:**
  - Tiêu đề "Xác minh Email", hiển thị email nhận mã (ví dụ `user@gmail.com`).
  - 6 ô nhập mã OTP riêng biệt tự động nhảy con trỏ chuột sang ô kế tiếp.
  - Bộ đếm ngược thời gian gửi lại mã (Countdown Timer 60 giây).
  - Thông báo phản hồi khi mã OTP hết hạn hoặc nhập sai.
- **Nút bấm & Tương tác:**
  - 6 ô nhập số (hỗ trợ paste toàn bộ mã 6 chữ số).
  - Nút "Gửi lại mã" (chỉ kích hoạt khi đồng hồ đếm ngược về 0).
  - Nút "Xác nhận mã": Kiểm tra tính hợp lệ của OTP trên Firestore và chuyển sang màn hình Đặt lại mật khẩu.

#### 20. Màn hình Đặt lại Mật khẩu Mới (`auth/reset_password_screen.dart`)
- **Dữ liệu hiển thị:**
  - Ô nhập Mật khẩu mới và Ô nhập lại Mật khẩu mới.
  - Tiêu chuẩn mật khẩu an toàn (ít nhất 6 ký tự, có chữ và số).
- **Nút bấm & Tương tác:**
  - Nút "Cập nhật mật khẩu mới": Gọi dịch vụ xác thực cập nhật mật khẩu, hiển thị thông báo thành công và điều hướng trở lại màn hình Đăng nhập.

---

### 4.5. Nhóm Thiết lập Ban đầu - Setup Wizard

#### 21. Thiết lập Hồ sơ Cá nhân (`setup/profile_setup_screen.dart`)
- **Dữ liệu hiển thị:** Bước 1/3 của Wizard. Ô nhập tên hiển thị, đơn vị tiền tệ chính (VNĐ / USD), mức thu nhập ước tính hàng tháng.
- **Nút bấm & Tương tác:** Nút "Tiếp tục" chuyển sang bước thiết lập ví.

#### 22. Thiết lập Ví Tiền Ban đầu (`setup/wallet_setup_screen.dart`)
- **Dữ liệu hiển thị:** Bước 2/3. Chọn các loại ví mặc định muốn tạo (Ví Tiền mặt, Tài khoản Ngân hàng, Thẻ tín dụng...) và nhập số dư ban đầu cho từng ví.
- **Nút bấm & Tương tác:** Thêm/bớt ví, nút "Tiếp tục".

#### 23. Thiết lập Danh mục Thu Chi (`setup/category_setup_screen.dart`)
- **Dữ liệu hiển thị:** Bước 3/3. Bảng các gói danh mục mẫu (Gói cơ bản, Gói sinh viên, Gói gia đình, Gói người đi làm). Người dùng có thể tích chọn nhanh những danh mục mình thường dùng.
- **Nút bấm & Tương tác:** Nút "Hoàn tất": Khởi tạo dữ liệu vào Firestore và đưa người dùng vào màn hình chính.

---

### 4.6. Nhóm Hồ sơ Cá nhân, Bảo mật & Cài đặt

#### 24. Màn hình Cá nhân (`profile_screen.dart`)
- **Dữ liệu hiển thị:**
  - Khung Hồ sơ Người dùng (Profile Header): Avatar tròn (kèm ảnh chụp thật hoặc chữ cái đầu), họ tên, email đăng nhập, huy hiệu tài khoản ("Hội viên FinAI"), trạng thái bảo mật tài khoản.
  - Snapshot Tài chính Nhanh (Financial Snapshot): Thẻ tóm tắt 3 chỉ số quan trọng trong tháng: Tổng tài sản ròng, Dòng tiền ròng tháng này, và Số ngân sách đang theo dõi.
  - Nhóm 1: Quản lý Tài chính (Ví tiền, Danh mục, Ngân sách, Mục tiêu tiết kiệm, Giao dịch định kỳ).
  - Nhóm 2: Trí tuệ Nhân tạo AI (Báo cáo tài chính AI, Phân tích chuyên sâu & Sức khỏe tài chính, Trò chuyện cùng FinAI).
  - Nhóm 3: Cài đặt Tài khoản & Bảo mật (Thông tin cá nhân, Bảo mật tài khoản, Thông báo hệ thống).
  - Nhóm 4: Giao diện & Hệ thống: Công tắc chuyển đổi Chế độ Tối (Dark Mode toggle), Giới thiệu ứng dụng.
  - Nhóm 5: Đăng xuất tài khoản.
- **Nút bấm & Tương tác:**
  - Chạm vào từng mục để điều hướng đến màn hình tương ứng.
  - Switch đổi chế độ sáng/tối tức thì không cần khởi động lại app.
  - Nút "Đăng xuất": Mở hộp thoại xác nhận chuyên nghiệp, có loading indicator và xoá sạch navigation stack đưa về màn hình Đăng nhập.

#### 25. Màn hình Thông tin Cá nhân (`personal_info_screen.dart`)
- **Dữ liệu hiển thị:**
  - Avatar lớn kèm nút camera để thay đổi ảnh đại diện.
  - Trường Họ và tên đầy đủ.
  - Trường Email (trạng thái khóa chỉ đọc, kèm huy hiệu "Đã xác thực").
  - Trường Số điện thoại liên hệ.
  - Trường Nghề nghiệp / Lĩnh vực công việc.
  - Trường Mức thu nhập hàng tháng (hỗ trợ cho AI phân tích tài chính).
  - Trường Mục tiêu tài chính chính (Tích luỹ mua nhà, trả nợ, đầu tư...).
- **Nút bấm & Tương tác:**
  - Nút đổi ảnh avatar (máy ảnh / thư viện ảnh).
  - Các ô nhập văn bản.
  - Nút "Lưu thay đổi": Cập nhật tức thì vào Firestore `users` collection và hiển thị Snackbar thành công.

#### 26. Màn hình Bảo mật Tài khoản (`account_security_screen.dart`)
- **Dữ liệu hiển thị:**
  - Thẻ tóm tắt bảo mật: Ngày tạo tài khoản, phương thức đăng nhập đang dùng (Email & Mật khẩu hoặc Google Auth).
  - Khu vực Đổi Mật khẩu: Ô nhập Mật khẩu hiện tại, Ô nhập Mật khẩu mới, Ô xác nhận Mật khẩu mới.
  - Thước đo độ mạnh mật khẩu mới (Strength bar).
  - Danh mục Mẹo bảo mật tài chính (Security tips): Không chia sẻ OTP, định kỳ đổi mật khẩu...
- **Nút bấm & Tương tác:**
  - Nút con mắt ẩn/hiện trên cả 3 ô mật khẩu.
  - Nút "Cập nhật mật khẩu": Xác thực mật khẩu cũ với Firebase Auth, ghi nhận mật khẩu mới và gửi phản hồi.

#### 27. Màn hình Thông báo Hệ thống (`notification_screen.dart`)
- **Dữ liệu hiển thị:**
  - Danh sách thông báo dạng Stream thời gian thực: Cảnh báo sắp vượt ngân sách, thông báo giao dịch định kỳ đến hạn, lời khuyên tài chính hàng tuần từ AI.
  - Icon phân loại theo mức độ: Cảnh báo (vàng), Khẩn cấp (đỏ), Thông tin (xanh), Thành công (xanh lá).
  - Trạng thái đã đọc / chưa đọc.
- **Nút bấm & Tương tác:**
  - Chạm vào thông báo để đánh dấu đã đọc hoặc điều hướng tới giao dịch/ngân sách liên quan.
  - Nút "Đánh dấu tất cả đã đọc" trên AppBar.
  - Nút "Xoá tất cả thông báo".

#### 28. Màn hình Giới thiệu Ứng dụng (`about_app_screen.dart`)
- **Dữ liệu hiển thị:**
  - Logo FinAI, Phiên bản phát hành (v1.0.0+1).
  - Thông tin sứ mệnh ứng dụng: Tối ưu hoá quản lý tài chính cá nhân người Việt qua AI.
  - Đội ngũ phát triển và kênh hỗ trợ.
  - Danh sách liên kết: Điều khoản sử dụng, Chính sách quyền riêng tư, Giấy phép mã nguồn mở.
- **Nút bấm & Tương tác:**
  - Nút mở liên kết Điều khoản dịch vụ và Chính sách bảo mật.
  - Nút "Liên hệ hỗ trợ": Mở trình soạn thư email hoặc website hỗ trợ.

---

## 5. DANH MỤC THƯ VIỆN COMPONENT & WIDGET DÙNG CHUNG (18 WIDGETS)

Dự án sở hữu bộ Widget tái sử dụng cao trong thư mục `lib/widgets/`:

| Tên Widget File | Vai trò kỹ thuật & Trải nghiệm UI |
| :--- | :--- |
| `app_button.dart` | Nút bấm chuẩn hoá Fintech: hỗ trợ Primary, Secondary, Outline, tự động hiển thị Loading spinner và chặn double-tap. |
| `app_card.dart` | Thẻ chứa nội dung với bo góc chuẩn, viền hairline tinh tế, tự thích ứng màu nền theo Dark/Light mode, không dùng bóng đổ nặng. |
| `app_empty_state.dart` | Giao diện hiển thị trạng thái rỗng (chưa có giao dịch, chưa có ngân sách...) với icon thân thiện, lời dẫn và nút kêu gọi hành động (CTA). |
| `app_section_header.dart` | Tiêu đề phân đoạn nội dung kèm nút hành động phụ (ví dụ "Xem tất cả", "Thêm"). |
| `app_snackbar.dart` | Thông báo nổi (Floating Snackbar) với 3 trạng thái: Thành công (xanh lá), Thất bại (đỏ), Cảnh báo (vàng cam). |
| `app_text_field.dart` | Ô nhập liệu chuẩn: nhãn nổi, icon đầu/cuối, thông báo lỗi validation, tối ưu màu nền input fill. |
| `budget_month_selector.dart` | Thanh điều hướng chọn tháng/năm dạng cuộn mượt mà dành riêng cho mô-đun Ngân sách. |
| `budget_progress_card.dart` | Thẻ hiển thị thanh tiến độ chi tiêu danh mục so với ngân sách hạn mức với chỉ số % đổi màu thông minh. |
| `custom_numpad.dart` | Bộ bàn phím số tài chính xúc giác gắn liền trên màn hình, hỗ trợ nhập số tiền nhanh không bị giật bàn phím hệ điều hành. |
| `dashboard_chart.dart` | Component bao đóng biểu đồ tài chính, tối ưu hóa kích thước và căn chỉnh nhãn trục X, Y cho di động. |
| `main_navigation.dart` | Thanh điều hướng dưới đáy 5 tab, tích hợp nút thêm nhanh (+) hình giọt nước/bo góc nổi bật ở vị trí trung tâm. |
| `quick_template_chip.dart` | Chip bấm chọn nhanh các mẫu chi tiêu thường nhật để điền form tự động trong 0.5 giây. |
| `spending_trend_bar_chart.dart` | Biểu đồ cột đôi so sánh thu - chi qua 6 tháng liên tiếp xây dựng trên nền tảng `fl_chart`. |
| `stream_error_widget.dart` | Thẻ thông báo lỗi thân thiện khi mất kết nối mạng hoặc lỗi stream Firebase, kèm nút "Thử lại". |
| `transaction_card.dart` | Thẻ giao dịch tiêu chuẩn: hiển thị icon tròn danh mục, tiêu đề, ví nguồn, thời gian và số tiền âm/dương định dạng chuẩn Việt Nam Đồng. |
| `trend_chart_card.dart` | Thẻ bọc ngoài cho các đồ thị xu hướng tài chính với tiêu đề, chú thích và nút phóng to/thu nhỏ. |
| `wallet_card.dart` | Thẻ mô phỏng thẻ ATM / Thẻ ngân hàng với logo loại ví, số dư và số hiệu thẻ che bảo mật (`•••• 8899`). |
| `weekly_heatmap_card.dart` | Biểu đồ nhiệt ma trận chi tiêu hàng tuần dùng `CustomPainter` thuần, giúp trực quan hóa cường độ chi tiêu theo từng ngày. |

---

## 6. ĐÁNH GIÁ UI/UX & KHUYẾN NGHỊ LỘ TRÌNH NÂNG CẤP

### 6.1. Điểm mạnh nổi bật hiện tại
1. **Tính hoàn thiện chức năng rất cao:** Đầy đủ từ quản lý dòng tiền vi mô (từng khoản thu/chi), trung mô (ví, danh mục, ngân sách, mục tiêu) đến vĩ mô (phân tích AI, điểm sức khỏe tài chính, dự báo dòng tiền).
2. **Công nghệ AI áp dụng thực chất:** 
   - Gemini API được cấp ngữ cảnh tài chính thực (`FinancialChatContextService`), không trả lời chung chung.
   - On-device OCR bằng ML Kit quét hóa đơn thật, nhận diện số tiền và cửa hàng tự động.
   - Tự động phát hiện chi tiêu bất thường (Anomaly Detection) ngay khi người dùng đang nhập số tiền.
3. **Thiết kế chuẩn Fintech:** Bộ màu Petrol `#1F6F8B`, viền mỏng hairline, số liệu tài chính canh hàng chuẩn (`tabularFigures`), hỗ trợ cả Light & Dark mode liền mạch.
4. **Độ an toàn dữ liệu:** 152/152 Unit & Widget Test tự động đều vượt qua (Passing 100%), quy trình xử lý giao dịch định kỳ Firestore mang tính nguyên tử (Atomic & Idempotent).

### 6.2. Các điểm có thể cải thiện thêm trong tương lai
1. **Animations & Micro-interactions:** Bổ sung hiệu ứng rung nhẹ (Haptic Feedback) khi bấm phím Numpad hoặc khi quét mã hóa đơn thành công.
2. **Biểu đồ nến / Phân tích đầu tư (Nếu muốn mở rộng):** Nếu trong tương lai người dùng muốn có tính năng "Phân tích chart để trade" như đã nhắc trong câu hỏi, dự án có thể tích hợp thêm API tài chính chứng khoán (như SSI, TCBS hoặc Yahoo Finance) cùng thư viện `interactive_chart` để vẽ biểu đồ nến K-line cho cổ phiếu/vàng/ngoại tệ. Hiện tại dự án đang tập trung 100% vào Dòng tiền cá nhân.
3. **Tiện ích Widget màn hình chính (Home Screen Widget):** Bổ sung Android AppWidget / iOS WidgetKit để người dùng xem nhanh số dư và nút bấm ghi nhanh 1 khoản chi tiêu ngay ngoài màn hình điện thoại mà không cần mở app.

---
*Báo cáo được tổng hợp tự động từ cấu trúc mã nguồn thực tế của dự án `finance_ai_app`.*
