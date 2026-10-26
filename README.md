# Rung Chuông Vàng — Vercel + Supabase

Giữ nguyên giao diện gốc. Phiên bản này dùng Vercel Serverless Functions + Supabase Postgres, trình duyệt đồng bộ bằng polling mỗi 1,5 giây (không dùng Socket.IO). Hỗ trợ 48 học sinh mỗi phòng.

## 1. Tạo bảng
Trong Supabase > SQL Editor, chạy toàn bộ `supabase.sql`. Các bảng `rcv_game_*` mới không ghi đè những bảng `rcv_*` hoặc `exam_*` đang có.

## 2. Đưa lên GitHub
Giải nén ZIP, tải **nội dung bên trong** lên repository `tamvan986/rungchuongvang`, giữ nguyên các thư mục `api/` và `public/`.

## 3. Vercel
Import repository trên Vercel. Framework Preset: Other; Root Directory: `./`; Build Command: để trống; Output Directory: để trống.

Trong Settings > Environment Variables, đặt:

- `SUPABASE_URL`: Project URL ở Supabase > Settings > Data API.
- `SUPABASE_SECRET_KEY`: khóa **service_role** (legacy JWT service_role) từ Supabase > Settings > API Keys > Legacy anon, service_role API keys. Đây là bí mật, **chỉ lưu trong Vercel**, không đăng GitHub hay gửi trong chat.
- `SESSION_SECRET`: chuỗi ngẫu nhiên dài ít nhất 32 ký tự, chỉ lưu trong Vercel.

Sau khi cấu hình, Redeploy. Địa chỉ giáo viên và QR sẽ dùng tên miền `https://...vercel.app`.

## 4. Thử nghiệm
Mở trang chủ > Tạo phòng giáo viên. Dùng điện thoại khác mở link QR > nhập tên > Vào thi. Bấm Bắt đầu, nộp đáp án, chờ chốt câu. Kiểm tra đồng bộ với 2–3 thiết bị trước, sau đó thử tải 48 thiết bị.

## Lưu ý
- Trạng thái lưu trong Supabase, không mất khi Vercel khởi động lại.
- Đồng bộ theo chu kỳ 1,5 giây, không phải WebSocket tức thời; cần mạng ổn định.
- Khi hết giờ, kết quả được chốt ở lần truy vấn tiếp theo (không cần máy giáo viên mở liên tục).
- Học sinh không thấy đáp án đúng trước khi chốt; chỉ API máy chủ dùng service_role.
- Phiên học sinh/giáo viên được lưu trên thiết bị trong 24 giờ; cần bảo vệ thiết bị giáo viên. Chưa có tài khoản giáo viên, chống gian lận nâng cao, hoặc phục hồi phiên trên thiết bị mới.
- Phiên bản lớp học thử nghiệm, chưa kiểm thử tải thực tế 48 thiết bị. Supabase/Vercel có thể có giới hạn miễn phí.
