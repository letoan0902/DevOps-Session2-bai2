# DevOps - Session 02 - Bài 2

Khởi tạo User thường và thiết lập đặc quyền quản trị (Sudoers Configuration) trên Ubuntu Server.

## Mô tả

Repository này chứa bài nộp Bài 2 của môn DevOps, Session 02. Nội dung gồm: tạo tài khoản non-root `devops` trên Droplet Ubuntu 24.04.3 LTS, thêm vào nhóm `sudo` để cấp đặc quyền quản trị an toàn, sao chép cấu hình SSH Key từ `root` sang `devops`, phân quyền chính xác thư mục `.ssh` và file `authorized_keys`, sau đó kiểm tra đăng nhập bằng SSH Key và lệnh `sudo whoami`.

## Mục lục

| Nội dung | Đường dẫn |
|---|---|
| Báo cáo và hướng dẫn chi tiết | [homework/session_02/ex2/README.md](homework/session_02/ex2/README.md) |
| Script tự động hóa (idempotent) | [homework/session_02/ex2/setup_devops_user.sh](homework/session_02/ex2/setup_devops_user.sh) |
| Log Terminal kiểm tra | [homework/session_02/ex2/terminal_log.txt](homework/session_02/ex2/terminal_log.txt) |

## Cấu trúc thư mục

```text
.
├── README.md
└── homework
    └── session_02
        └── ex2
            ├── README.md
            ├── setup_devops_user.sh
            └── terminal_log.txt
```
