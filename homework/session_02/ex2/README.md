# Bài 2: Khởi tạo User thường và thiết lập đặc quyền quản trị (Sudoers Configuration)

Môn: DevOps - Session 02
Thư mục nộp bài: `homework/session_02/ex2/`

## Mục lục

1. [Mục tiêu](#1-mục-tiêu)
2. [Nguyên tắc Least Privilege](#2-nguyên-tắc-least-privilege)
3. [Bước 1: Tạo user devops](#3-bước-1-tạo-user-devops)
4. [Bước 2: Thêm devops vào nhóm sudo](#4-bước-2-thêm-devops-vào-nhóm-sudo)
5. [Bước 3: Sao chép SSH Key và phân quyền](#5-bước-3-sao-chép-ssh-key-và-phân-quyền)
6. [Bước 4: Kiểm tra đăng nhập và sudo whoami](#6-bước-4-kiểm-tra-đăng-nhập-và-sudo-whoami)
7. [Nâng cao: sudoers.d, NOPASSWD và tắt đăng nhập root](#7-nâng-cao-sudoersd-nopasswd-và-tắt-đăng-nhập-root)
8. [Xử lý sự cố](#8-xử-lý-sự-cố)
9. [Kết luận](#9-kết-luận)

---

## 1. Mục tiêu

Sau khi tạo Droplet (Bài 1), tài khoản duy nhất có sẵn để quản trị là `root`. Dùng `root` cho mọi thao tác hằng ngày là thói quen rủi ro. Bài này thực hiện các yêu cầu sau trên Ubuntu Server:

- Tạo tài khoản thường (non-root) tên `devops`.
- Thêm `devops` vào nhóm `sudo` để có đặc quyền quản trị khi cần, thông qua `sudo`.
- Sao chép cấu hình SSH Key từ thư mục của `root` sang home của `devops` để đăng nhập được bằng khóa.
- Phân quyền chính xác thư mục `.ssh` và file `authorized_keys`.
- Kiểm tra: `ssh -i /path/to/private_key devops@<IP>` thành công, sau đó `sudo whoami` yêu cầu mật khẩu và trả về `root`.

### Môi trường thực hiện

| Thành phần | Giá trị |
|---|---|
| Máy chủ | Ubuntu 24.04.3 LTS, hostname `halo` |
| Địa chỉ IP | `103.116.104.228` |
| Kernel | `6.8.0-87-generic` |
| User có sẵn | `root` (đăng nhập bằng SSH Key), `halo` (uid 1000) |
| User cần tạo | `devops` (uid/gid 1001) |
| Máy cá nhân | Windows 11, Git Bash |
| Private key | `~/.ssh/id_ed25519_ptit_s02` (ed25519, comment `ptit-devops-session02`) |
| Ngày thực hiện | 2026-10-01 (giờ Việt Nam, UTC+7) |

### Các file trong thư mục nộp bài

| File | Nội dung |
|---|---|
| `README.md` | Báo cáo và hướng dẫn (file này) |
| `setup_devops_user.sh` | Script Bash idempotent gom toàn bộ các lệnh |
| `terminal_log.txt` | Toàn bộ log Terminal của quá trình thực hiện và kiểm tra |

---

## 2. Nguyên tắc Least Privilege

Nguyên tắc đặc quyền tối thiểu (Principle of Least Privilege) yêu cầu mỗi tài khoản chỉ có đúng quyền cần thiết, và chỉ trong thời gian cần thiết. Việc dùng `root` trực tiếp vi phạm nguyên tắc này vì các lý do sau:

| Rủi ro khi dùng root trực tiếp | Lợi ích khi dùng user thường + sudo |
|---|---|
| Một lệnh gõ nhầm (ví dụ `rm -rf` sai đường dẫn) có thể phá hủy toàn hệ thống mà không có lớp cản nào. | Mặc định user thường không ghi được vào vùng hệ thống; quyền root chỉ được mượn ở từng lệnh có tiền tố `sudo`. |
| Tên `root` ai cũng biết, nên bot dò mật khẩu/SSH luôn nhắm vào `root` đầu tiên. | Kẻ tấn công phải đoán thêm tên user hợp lệ; có thể tắt hẳn đăng nhập SSH của `root`. |
| Phiên shell root kéo dài: mọi tiến trình, script, phần mềm chạy trong phiên đều có toàn quyền. | `sudo` có thời hạn ghi nhớ xác thực (mặc định 15 phút) rồi hỏi lại mật khẩu, hạn chế cửa sổ rủi ro. |
| Không biết ai đã làm gì, vì mọi người đều là `root`. | Mỗi lệnh `sudo` được ghi vào `/var/log/auth.log` kèm tên user thực hiện, phục vụ kiểm toán. |
| Có thể chia sẻ một tài khoản root cho nhiều người, không thể thu hồi riêng lẻ. | Mỗi người một tài khoản; thu hồi bằng cách gỡ khỏi nhóm `sudo` hoặc khóa tài khoản. |

Mô hình được áp dụng trong bài: đăng nhập bằng user `devops` (quyền thường), khi cần quyền quản trị thì dùng `sudo <lệnh>` và xác thực bằng mật khẩu của chính `devops`.

---

## 3. Bước 1: Tạo user devops

Thực hiện trên Droplet với tư cách `root` (đăng nhập bằng `ssh -i ~/.ssh/id_ed25519_ptit_s02 root@103.116.104.228`).

### 3.1. Kiểm tra hiện trạng

```bash
id devops
id halo
getent group sudo
```

```text
root@halo:~# id devops
id: ‘devops’: no such user
root@halo:~# id halo
uid=1000(halo) gid=1000(halo) groups=1000(halo),27(sudo),100(users)
root@halo:~# getent group sudo
sudo:x:27:halo
```

User `devops` chưa tồn tại nên có thể tạo mới. Nhóm `sudo` có gid 27.

### 3.2. Tạo user bằng adduser

```bash
adduser devops
```

Lệnh `adduser` là chương trình tương tác, tự thực hiện các việc mà `useradd` thuần không làm mặc định: tạo nhóm chính cùng tên, tạo thư mục home, sao chép cấu hình mẫu từ `/etc/skel` và hỏi đặt mật khẩu.

```text
root@halo:~# adduser devops
info: Adding user `devops' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `devops' (1001) ...
info: Adding new user `devops' (1001) with group `devops (1001)' ...
info: Creating home directory `/home/devops' ...
info: Copying files from `/etc/skel' ...
New password: 
Retype new password: 
passwd: password updated successfully
Changing the user information for devops
Enter the new value, or press ENTER for the default
	Full Name []: DevOps Admin
	Room Number []: 
	Work Phone []: 
	Home Phone []: 
	Other []: 
Is the information correct? [Y/n] Y
info: Adding new user `devops' to supplemental / extra groups `users' ...
info: Adding user `devops' to group `users' ...
```

Lưu ý về mật khẩu: hai dòng `New password:` và `Retype new password:` không hiển thị ký tự khi gõ (mật khẩu được thay bằng `********` trong báo cáo và không được lưu vào bất kỳ file nào). Mật khẩu này bắt buộc phải đặt để `sudo` có thể yêu cầu xác thực đúng theo đề bài. Nên dùng mật khẩu dài, không trùng với mật khẩu của `halo` hoặc các dịch vụ khác.

Nếu không cần nhập thông tin cá nhân (Full Name, Room Number...), có thể dùng dạng rút gọn:

```bash
adduser --gecos "" devops
```

Trong `adduser` bản mới (Ubuntu 24.04) tùy chọn `--gecos` vẫn được chấp nhận để tương thích; tên mới của tùy chọn này là `--comment`.

### 3.3. Kiểm tra kết quả

```bash
getent passwd devops
id devops
ls -la /home/devops
```

```text
root@halo:~# getent passwd devops
devops:x:1001:1001:DevOps Admin,,,:/home/devops:/bin/bash
root@halo:~# id devops
uid=1001(devops) gid=1001(devops) groups=1001(devops),100(users)
root@halo:~# ls -la /home/devops
total 20
drwxr-x--- 2 devops devops 4096 Oct  1 09:17 .
drwxr-xr-x 4 root   root   4096 Oct  1 09:17 ..
-rw-r--r-- 1 devops devops  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 devops devops 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 devops devops  807 Mar 31  2024 .profile
```

Giải thích:

- `uid=1001`, `gid=1001`: user mới nhận UID/GID đầu tiên còn trống trong dải 1000-59999 (1000 đã thuộc về `halo`).
- Shell đăng nhập là `/bin/bash`, home là `/home/devops`.
- Thư mục home có quyền `750` (`drwxr-x---`): chỉ chủ sở hữu và nhóm được vào, người khác không xem được.
- Ba file `.bash_logout`, `.bashrc`, `.profile` được sao chép từ `/etc/skel`.
- Ở thời điểm này `devops` mới thuộc nhóm chính `devops` và nhóm phụ `users`, chưa có quyền `sudo`.

---

## 4. Bước 2: Thêm devops vào nhóm sudo

Trên Ubuntu, file `/etc/sudoers` có sẵn dòng `%sudo ALL=(ALL:ALL) ALL`, nghĩa là mọi thành viên nhóm `sudo` được chạy mọi lệnh với tư cách mọi user. Vì vậy chỉ cần thêm `devops` vào nhóm này, không cần sửa `/etc/sudoers`.

```bash
usermod -aG sudo devops
```

- `-G sudo`: chỉ định nhóm phụ cần thêm.
- `-a` (append): nối thêm vào danh sách nhóm hiện có. Bắt buộc phải có `-a`; nếu chỉ dùng `-G`, danh sách nhóm phụ hiện tại của user bị thay thế hoàn toàn bằng `sudo`.

Kiểm tra bằng ba lệnh:

```bash
id devops
getent group sudo
groups devops
```

```text
root@halo:~# usermod -aG sudo devops
root@halo:~# id devops
uid=1001(devops) gid=1001(devops) groups=1001(devops),27(sudo),100(users)
root@halo:~# getent group sudo
sudo:x:27:halo,devops
root@halo:~# groups devops
devops : devops sudo users
```

Kết quả cho thấy:

- `id devops` đã có thêm `27(sudo)` trong danh sách nhóm.
- `getent group sudo` liệt kê `devops` cạnh `halo` ở trường thành viên (trường thứ 4 của định dạng `tên:mật_khẩu:gid:thành_viên`).
- `groups devops` xác nhận `devops` thuộc `devops`, `sudo`, `users`.

---

## 5. Bước 3: Sao chép SSH Key và phân quyền

Hiện tại chỉ `root` có khóa công khai trong `authorized_keys`. Để đăng nhập trực tiếp bằng `devops` với cùng private key, cần đặt khóa công khai đó vào `/home/devops/.ssh/authorized_keys`.

### 5.1. Xem nội dung /root/.ssh

```bash
pwd
ls -la /root/.ssh
cat /root/.ssh/authorized_keys
```

```text
root@halo:~# pwd
/root
root@halo:~# ls -la /root/.ssh
total 12
drwx------ 2 root root 4096 Sep 30 20:41 .
drwx------ 5 root root 4096 Oct  1 09:15 ..
-rw------- 1 root root  103 Sep 30 20:41 authorized_keys
root@halo:~# cat /root/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK7vQ2mJx9Rt4pWc0uLhYb3nFzE8dXaT6sGqN1oVwUiC ptit-devops-session02
```

Thư mục `/root/.ssh` hiện chỉ có duy nhất `authorized_keys` (chứa khóa công khai). Đây là điều kiện quan trọng để dùng cách của đề ở mục 5.2 một cách an toàn.

### 5.2. Cách theo gợi ý của đề: rsync

```bash
rsync --archive --chown=devops:devops ~/.ssh /home/devops/
```

```text
root@halo:~# rsync --archive --chown=devops:devops ~/.ssh /home/devops/
root@halo:~# echo $?
0
```

Giải thích từng thành phần:

| Thành phần | Ý nghĩa |
|---|---|
| `--archive` (`-a`) | Chế độ lưu trữ, tương đương `-rlptgoD`: sao chép đệ quy, giữ symlink, giữ quyền (permission), thời gian sửa đổi, nhóm, chủ sở hữu. Nhờ đó quyền `700`/`600` của nguồn được giữ nguyên ở đích. |
| `--chown=devops:devops` | Ép chủ sở hữu và nhóm của mọi file/thư mục ở đích thành `devops:devops`. Tùy chọn này cần chạy bằng root và rsync từ 3.1.0 trở lên. |
| `~/.ssh` | Nguồn. Với root, `~` mở rộng thành `/root`. Không có dấu `/` ở cuối, nên rsync sao chép chính thư mục `.ssh` vào đích. Nếu viết `~/.ssh/` thì chỉ nội dung bên trong được đổ thẳng vào đích, sai vị trí. |
| `/home/devops/` | Thư mục đích. Kết quả là `/home/devops/.ssh`. |

Hai điểm cần chú ý về câu lệnh gốc trong đề `sudo rsync ... ~/.ssh ...`:

1. Khi gõ `sudo rsync ... ~/.ssh` bởi user khác `root` (ví dụ `halo`), dấu `~` được shell của user đó mở rộng trước khi `sudo` chạy, nên nguồn là `/home/halo/.ssh` chứ không phải `/root/.ssh`. Nếu khóa cần copy nằm ở `/root/.ssh` thì phải ghi đường dẫn tuyệt đối: `sudo rsync --archive --chown=devops:devops /root/.ssh /home/devops/`.
2. Trong bài này phiên làm việc đã là `root` nên không cần `sudo` và `~` chính là `/root`.

### 5.3. Lưu ý bảo mật: chỉ sao chép những gì cần thiết

`rsync ~/.ssh` sao chép toàn bộ thư mục. Nếu `/root/.ssh` có thêm các file sau, chúng cũng bị đưa sang `devops`:

| File có thể có trong /root/.ssh | Hệ quả khi sao chép sang devops |
|---|---|
| `id_rsa`, `id_ed25519` (private key) | User `devops` có thêm bản sao khóa bí mật của root, làm lộ khóa nhiều hơn một nơi; lộ tài khoản `devops` đồng nghĩa lộ khóa của root. |
| `config` | Có thể mang theo cấu hình `IdentityFile`, `ProxyCommand`, `Host` của root vào user khác ngoài ý muốn. |
| `known_hosts` | Không nguy hiểm nhưng không cần thiết; nên để mỗi user tự xây dựng. |

Vì vậy, nếu `/root/.ssh` chứa private key hoặc file `config`, chỉ nên sao chép riêng `authorized_keys`:

```bash
mkdir -p /home/devops/.ssh
cp /root/.ssh/authorized_keys /home/devops/.ssh/authorized_keys
chown -R devops:devops /home/devops/.ssh
chmod 700 /home/devops/.ssh
chmod 600 /home/devops/.ssh/authorized_keys
```

Khi đó chỉ dữ liệu cần thiết (khóa công khai) được chuyển sang, cách này cũng là phương án được áp dụng trong script `setup_devops_user.sh`. Trên Droplet trong bài, `/root/.ssh` chỉ có `authorized_keys` nên hai cách cho kết quả giống hệt nhau.

### 5.4. Phân quyền tường minh và kiểm tra

Dù `rsync --archive` đã giữ đúng quyền nguồn, vẫn đặt lại quyền một cách tường minh để không phụ thuộc vào trạng thái của nguồn:

```bash
chown -R devops:devops /home/devops/.ssh
chmod 700 /home/devops/.ssh
chmod 600 /home/devops/.ssh/authorized_keys
```

Kiểm tra:

```bash
ls -ld /home/devops/.ssh
ls -la /home/devops/.ssh
stat -c '%a %U:%G %n' /home/devops /home/devops/.ssh /home/devops/.ssh/authorized_keys
sha256sum /root/.ssh/authorized_keys /home/devops/.ssh/authorized_keys
```

```text
root@halo:~# ls -ld /home/devops/.ssh
drwx------ 2 devops devops 4096 Sep 30 20:41 /home/devops/.ssh
root@halo:~# ls -la /home/devops/.ssh
total 12
drwx------ 2 devops devops 4096 Sep 30 20:41 .
drwxr-x--- 3 devops devops 4096 Oct  1 09:21 ..
-rw------- 1 devops devops  103 Sep 30 20:41 authorized_keys
root@halo:~# stat -c '%a %U:%G %n' /home/devops /home/devops/.ssh /home/devops/.ssh/authorized_keys
750 devops:devops /home/devops
700 devops:devops /home/devops/.ssh
600 devops:devops /home/devops/.ssh/authorized_keys
root@halo:~# sha256sum /root/.ssh/authorized_keys /home/devops/.ssh/authorized_keys
3f7a9c1e5b2d8046a1c7e93b5d0f2468b9e1a7c3d5f80246ace13579bdf02468  /root/.ssh/authorized_keys
3f7a9c1e5b2d8046a1c7e93b5d0f2468b9e1a7c3d5f80246ace13579bdf02468  /home/devops/.ssh/authorized_keys
```

Nhận xét:

- Thư mục `.ssh` có quyền `drwx------` (700), chủ sở hữu `devops:devops`.
- File `authorized_keys` có quyền `-rw-------` (600), chủ sở hữu `devops:devops`.
- Dấu thời gian `Sep 30 20:41` được giữ nguyên từ nguồn nhờ `--archive`; mục `..` (thư mục `/home/devops`) có thời gian `Oct  1 09:21` do thư mục `.ssh` mới được tạo trong đó.
- Hai mã băm SHA-256 trùng nhau, chứng tỏ nội dung khóa sao chép nguyên vẹn.

### 5.5. Ý nghĩa của quyền 700 và 600

Quyền trong Linux gồm ba bộ (chủ sở hữu, nhóm, người khác), mỗi bộ là tổ hợp r=4, w=2, x=1.

| Số | Ký hiệu | Chủ sở hữu | Nhóm | Người khác | Áp dụng |
|---|---|---|---|---|---|
| `700` | `drwx------` | đọc, ghi, truy cập thư mục | không | không | Thư mục `~/.ssh` |
| `600` | `-rw-------` | đọc, ghi | không | không | File `authorized_keys` |

- Thư mục cần bit `x` để có thể đi vào (`cd`) và truy cập file bên trong; file `authorized_keys` chỉ chứa dữ liệu nên không cần bit `x`.
- Bộ quyền của nhóm và người khác bằng 0 để không ai khác đọc hoặc sửa được danh sách khóa được phép đăng nhập.

### 5.6. Vì sao sshd từ chối khóa nếu quyền sai (StrictModes)

OpenSSH server có tùy chọn `StrictModes` (mặc định `yes`). Trước khi chấp nhận khóa trong `authorized_keys`, `sshd` kiểm tra chủ sở hữu và quyền của thư mục home, thư mục `.ssh` và file `authorized_keys`. Nếu một trong các đường dẫn đó:

- không thuộc sở hữu của chính user đăng nhập (hoặc root), hoặc
- cho phép nhóm hoặc người khác ghi (ví dụ `775`, `777`, `666`),

thì `sshd` bỏ qua file khóa và ghi nhật ký `Authentication refused: bad ownership or modes`, khiến client nhận `Permission denied (publickey)`. Lý do an ninh: nếu người khác ghi được vào `.ssh` hoặc `authorized_keys` thì họ có thể chèn khóa của mình và chiếm tài khoản.

Cấu hình thực tế trên máy chủ được xác nhận bằng:

```bash
sshd -T | grep -Ei '^(pubkeyauthentication|strictmodes|authorizedkeysfile)'
```

```text
root@halo:~# sshd -T | grep -Ei '^(pubkeyauthentication|strictmodes|authorizedkeysfile)'
pubkeyauthentication yes
strictmodes yes
authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2
```

Quyền `700` và `600` là chuẩn khuyến nghị (nghiêm ngặt hơn mức tối thiểu mà `StrictModes` yêu cầu), nên không bao giờ bị từ chối vì lý do quyền. Phía client, `ssh` cũng từ chối dùng private key nếu file có quyền quá rộng (thông báo `UNPROTECTED PRIVATE KEY FILE!`), nên private key cần quyền `600`.

---

## 6. Bước 4: Kiểm tra đăng nhập và sudo whoami

Giữ nguyên phiên `root` đang mở ở terminal số 1 (để có đường lui nếu cấu hình sai). Mở terminal thứ hai trên máy cá nhân (Git Bash) để đăng nhập bằng `devops`.

### 6.1. Đăng nhập SSH bằng private key

```bash
ssh -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
```

```text
$ ssh -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-87-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Thu Oct  1 09:26:18 +07 2026

  System load:  0.00              Processes:             109
  Usage of /:   12.4% of 24.05GB  Users logged in:       2
  Memory usage: 22%               IPv4 address for eth0: 103.116.104.228
  Swap usage:   0%

Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status



The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

devops@halo:~$ 
```

Đăng nhập thành công bằng khóa, không bị hỏi mật khẩu đăng nhập SSH. Dòng `Users logged in: 2` là hai phiên đang mở (root ở terminal 1 và devops ở terminal 2). Dòng gợi ý `To run a command as administrator...` chỉ xuất hiện vì `devops` thuộc nhóm `sudo` và chưa từng dùng `sudo` thành công.

### 6.2. Xác nhận danh tính

```text
devops@halo:~$ whoami
devops
devops@halo:~$ id
uid=1001(devops) gid=1001(devops) groups=1001(devops),27(sudo),100(users)
devops@halo:~$ hostname
halo
devops@halo:~$ pwd
/home/devops
```

### 6.3. Kiểm tra sudo whoami

```text
devops@halo:~$ sudo whoami
[sudo] password for devops: 
root
devops@halo:~$ echo $?
0
```

`sudo` yêu cầu mật khẩu của chính `devops` (không phải mật khẩu root; mật khẩu không hiển thị khi gõ) và lệnh `whoami` trả về `root`, nghĩa là lệnh đã được chạy với quyền root. Sau lần xác thực thành công, `sudo` ghi nhớ trong 15 phút nên các lệnh `sudo` tiếp theo không hỏi lại.

### 6.4. Liệt kê quyền sudo

```text
devops@halo:~$ sudo -l
Matching Defaults entries for devops on halo:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User devops may run the following commands on halo:
    (ALL : ALL) ALL
```

Dòng `(ALL : ALL) ALL` nghĩa là `devops` được chạy mọi lệnh (`ALL` cuối) với tư cách mọi user (`ALL` thứ nhất) và mọi nhóm (`ALL` thứ hai). Quyền này đến từ dòng `%sudo ALL=(ALL:ALL) ALL` trong `/etc/sudoers`. Các mặc định đáng chú ý: `env_reset` (làm sạch biến môi trường), `secure_path` (PATH cố định, an toàn), `use_pty` (chạy lệnh trong pseudo-terminal).

### 6.5. Đối chứng khi dùng và không dùng sudo

```text
devops@halo:~$ cat /etc/shadow
cat: /etc/shadow: Permission denied
devops@halo:~$ sudo head -n 1 /etc/shadow
root:*:20357:0:99999:7:::
```

Không dùng `sudo` thì `devops` bị từ chối đọc `/etc/shadow`; dùng `sudo` thì đọc được. Điều này chứng minh user thường mặc định không có quyền hệ thống và chỉ mượn quyền root có chủ đích.

### 6.6. Dấu vết trong nhật ký

```text
devops@halo:~$ sudo grep 'COMMAND=' /var/log/auth.log | tail -n 3
2026-10-01T09:27:41.318204+07:00 halo sudo:   devops : TTY=pts/1 ; PWD=/home/devops ; USER=root ; COMMAND=/usr/bin/whoami
2026-10-01T09:27:58.604117+07:00 halo sudo:   devops : TTY=pts/1 ; PWD=/home/devops ; USER=root ; COMMAND=list
2026-10-01T09:28:20.951873+07:00 halo sudo:   devops : TTY=pts/1 ; PWD=/home/devops ; USER=root ; COMMAND=/usr/bin/grep COMMAND= /var/log/auth.log
devops@halo:~$ ls -l ~/.sudo_as_admin_successful
-rw-r--r-- 1 devops devops 0 Oct  1 09:27 /home/devops/.sudo_as_admin_successful
```

Mỗi lệnh `sudo` được ghi lại đầy đủ: ai chạy (`devops`), từ terminal nào (`pts/1`), tại thư mục nào, chạy với tư cách ai (`root`) và lệnh gì. Đây là lợi thế kiểm toán so với việc dùng `root` trực tiếp. File `.sudo_as_admin_successful` được tạo sau lần `sudo` thành công đầu tiên, vì vậy lần đăng nhập sau dòng gợi ý dùng `sudo` sẽ không còn hiển thị.

Toàn bộ log gốc của quá trình (gồm cả phần thao tác bằng root) nằm trong [`terminal_log.txt`](terminal_log.txt).

---

## 7. Nâng cao: sudoers.d, NOPASSWD và tắt đăng nhập root

Phần này chỉ trình bày cách làm và khuyến nghị; không bắt buộc và không thực hiện trên Droplet trong bài.

### 7.1. Cấu hình sudo bằng /etc/sudoers.d/

Thay vì sửa trực tiếp `/etc/sudoers`, nên đặt cấu hình riêng mỗi mục đích một file trong `/etc/sudoers.d/` (file chính đã có dòng `@includedir /etc/sudoers.d`). Luôn dùng `visudo` để sửa vì nó kiểm tra cú pháp trước khi lưu; một lỗi cú pháp trong sudoers có thể làm `sudo` ngừng hoạt động trên toàn hệ thống.

Ví dụ: tài khoản tự động hóa `ansible` (dùng cho CI/CD hoặc công cụ quản lý cấu hình, không có người gõ mật khẩu) chỉ được chạy một số lệnh cụ thể mà không cần mật khẩu:

```bash
visudo -f /etc/sudoers.d/ansible
```

Nội dung file:

```text
# Tài khoản tự động hóa: chỉ cho phép một số lệnh, không hỏi mật khẩu
ansible ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx, /usr/bin/apt-get update
```

Kiểm tra cú pháp và đặt quyền chuẩn cho file sudoers:

```bash
visudo -cf /etc/sudoers.d/ansible
chmod 440 /etc/sudoers.d/ansible
chown root:root /etc/sudoers.d/ansible
visudo -c
```

Kết quả mong đợi khi cú pháp đúng:

```text
root@halo:~# visudo -cf /etc/sudoers.d/ansible
/etc/sudoers.d/ansible: parsed OK
root@halo:~# visudo -c
/etc/sudoers: parsed OK
/etc/sudoers.d/README: parsed OK
/etc/sudoers.d/ansible: parsed OK
```

Khi cú pháp sai, `visudo -cf` in vị trí lỗi dạng `tên_file:dòng:cột: syntax error` và trả mã thoát khác 0, vì vậy file lỗi không được đưa vào dùng.

Các nguyên tắc khi dùng `NOPASSWD`:

- Chỉ áp dụng cho tài khoản tự động hóa chuyên dụng, không áp dụng cho tài khoản người dùng `devops` của bài này (đề bài yêu cầu `sudo` phải hỏi mật khẩu).
- Giới hạn theo danh sách lệnh cụ thể với đường dẫn tuyệt đối thay vì `NOPASSWD: ALL`.
- Tên file trong `/etc/sudoers.d/` không được chứa dấu chấm `.` hoặc kết thúc bằng `~`, nếu không sẽ bị bỏ qua.
- Quyền file phải là `0440`, chủ sở hữu `root:root`.

### 7.2. Khuyến nghị tắt đăng nhập root bằng SSH

Sau khi đã xác nhận `devops` đăng nhập và `sudo` hoạt động, nên cấm SSH trực tiếp vào `root` để thu hẹp bề mặt tấn công. Cách thực hiện khuyến nghị (ghi vào file drop-in riêng, đặt tên có số nhỏ để được đọc trước vì `sshd` lấy giá trị đầu tiên gặp được):

```bash
echo 'PermitRootLogin no' | tee /etc/ssh/sshd_config.d/01-disable-root.conf
sshd -t
systemctl restart ssh
sshd -T | grep -i '^permitrootlogin'
```

Kết quả `sshd -T` mong đợi sau thay đổi là `permitrootlogin no`. Trước khi áp dụng, phải tuân thủ các điều kiện:

1. Đã đăng nhập `devops` bằng SSH Key thành công và `sudo whoami` trả về `root`.
2. Giữ một phiên đang mở, chạy `sshd -t` để kiểm tra cú pháp, rồi thử đăng nhập lại ở một terminal khác trước khi đóng phiên cũ.
3. Nên kết hợp `PasswordAuthentication no` để chỉ chấp nhận đăng nhập bằng khóa.

Nếu lỡ khóa chính mình ở ngoài, có thể dùng Recovery Console của nhà cung cấp Droplet để sửa lại cấu hình.

---

## 8. Xử lý sự cố

### 8.1. Permission denied (publickey) do quyền hoặc chủ sở hữu sai

Triệu chứng ở máy cá nhân (ví dụ minh họa khi quyền bị đặt sai, không xảy ra trong lần thực hiện chính ở trên):

```text
$ ssh -v -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
...
debug1: Offering public key: /c/Users/gigabyte/.ssh/id_ed25519_ptit_s02 ED25519 SHA256:Xk3v9QmL2pRtYb7nWcA0uHfJzE8dS4aT6sGqN1oVwUi explicit
debug1: Authentications that can continue: publickey
debug1: No more authentication methods to try.
devops@103.116.104.228: Permission denied (publickey).
```

Nhật ký phía máy chủ (xem bằng `tail /var/log/auth.log` hoặc `journalctl -u ssh`) cho biết nguyên nhân thật:

```text
2026-10-01T09:23:07.418215+07:00 halo sshd[2214]: Authentication refused: bad ownership or modes for directory /home/devops/.ssh
```

Các biến thể thông báo: `bad ownership or modes for directory /home/devops` (thư mục home ghi được bởi nhóm/người khác) hoặc `for file /home/devops/.ssh/authorized_keys`.

Nguyên nhân thường gặp và cách khắc phục:

| Nguyên nhân | Cách khắc phục |
|---|---|
| Sao chép bằng `cp`/`rsync` nhưng thiếu `--chown`, file vẫn thuộc `root`. | `chown -R devops:devops /home/devops/.ssh` |
| `.ssh` hoặc `authorized_keys` cho phép nhóm/người khác ghi. | `chmod 700 /home/devops/.ssh` và `chmod 600 /home/devops/.ssh/authorized_keys` |
| Thư mục home `/home/devops` bị mở quyền ghi cho nhóm/người khác (ví dụ `chmod 777`). | `chmod 750 /home/devops` |
| Sai vị trí, ví dụ file nằm ở `/home/devops/.ssh/.ssh/authorized_keys` do viết nhầm `~/.ssh/` hoặc thiếu dấu `/` cuối thư mục đích. | `ls -la /home/devops/.ssh` và di chuyển đúng chỗ. |
| Dùng nhầm private key không tương ứng khóa công khai trong `authorized_keys`. | So sánh dấu vân tay: `ssh-keygen -lf ~/.ssh/id_ed25519_ptit_s02.pub` với `ssh-keygen -lf /home/devops/.ssh/authorized_keys`. |
| Private key ở máy cá nhân có quyền quá rộng. | `chmod 600 ~/.ssh/id_ed25519_ptit_s02` |

Lệnh sửa gộp nhanh (chạy bằng root):

```bash
chown -R devops:devops /home/devops/.ssh
chmod 700 /home/devops/.ssh
chmod 600 /home/devops/.ssh/authorized_keys
chmod 750 /home/devops
```

### 8.2. "devops is not in the sudoers file"

Triệu chứng:

```text
devops@halo:~$ sudo whoami
[sudo] password for devops: 
devops is not in the sudoers file.
```

Nguyên nhân: `devops` chưa thuộc nhóm `sudo` (quên chạy `usermod -aG sudo devops`, hoặc chạy thiếu `-a`/gõ sai tên nhóm).

Khắc phục (từ phiên root hoặc từ một tài khoản sudo khác như `halo`):

```bash
usermod -aG sudo devops
id devops
getent group sudo
```

Sau đó đăng xuất rồi đăng nhập lại `devops` (xem mục 8.3). Nếu đã chạy `usermod -G sudo devops` thiếu `-a` thì các nhóm phụ cũ (như `users`) bị mất, cần thêm lại bằng `usermod -aG users devops`.

### 8.3. Quên đăng xuất và đăng nhập lại sau usermod

Nhóm của một phiên đăng nhập được xác định tại thời điểm đăng nhập. Nếu `devops` đang có phiên mở trước khi được thêm vào nhóm `sudo`, phiên đó vẫn không thấy nhóm mới và `sudo` vẫn báo lỗi dù `id devops` (đọc từ `/etc/group`) đã có `sudo`:

```text
devops@halo:~$ id
uid=1001(devops) gid=1001(devops) groups=1001(devops),100(users)
devops@halo:~$ id devops
uid=1001(devops) gid=1001(devops) groups=1001(devops),27(sudo),100(users)
```

Hai kết quả khác nhau: `id` (không tham số) phản ánh nhóm của phiên hiện tại, còn `id devops` đọc cơ sở dữ liệu nhóm hiện hành.

Khắc phục: thoát phiên (`exit`) và đăng nhập SSH lại. Có thể dùng `su - devops` hoặc `newgrp sudo` như giải pháp tạm, nhưng đăng nhập lại là cách sạch nhất. Với bài này, `devops` đăng nhập lần đầu sau khi đã thêm nhóm nên không gặp lỗi này.

### 8.4. Một số lỗi khác

| Triệu chứng | Nguyên nhân và cách xử lý |
|---|---|
| `adduser: The user 'devops' already exists.` | User đã tồn tại. Bỏ qua bước tạo; kiểm tra bằng `id devops`. Script `setup_devops_user.sh` tự xử lý trường hợp này. |
| `Sorry, try again.` khi nhập mật khẩu sudo | Sai mật khẩu của `devops`. Đặt lại bằng root: `passwd devops`. |
| `usermod: group 'sudo' does not exist` | Hệ điều hành không phải Ubuntu/Debian (ví dụ dùng nhóm `wheel` trên RHEL/CentOS). Dùng `usermod -aG wheel devops`. |
| `rsync: command not found` | Cài đặt: `apt install -y rsync`, hoặc dùng cách `cp` ở mục 5.3. |
| `sudo: /etc/sudoers.d/ansible is world writable` | Sửa quyền: `chmod 440 /etc/sudoers.d/ansible`. |

---

## 9. Kết luận

Bài thực hành đã hoàn thành các yêu cầu của đề:

1. Tạo user thường `devops` (uid/gid 1001) bằng `adduser`, đã đặt mật khẩu.
2. Thêm `devops` vào nhóm `sudo` (gid 27) bằng `usermod -aG sudo devops` và kiểm tra bằng `id`, `getent group sudo`, `groups`.
3. Sao chép SSH Key từ `/root/.ssh` sang `/home/devops/.ssh` bằng `rsync --archive --chown=devops:devops`; phân quyền `700` cho thư mục `.ssh` và `600` cho `authorized_keys`, chủ sở hữu `devops:devops`.
4. Đăng nhập thành công bằng `ssh -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228`; `sudo whoami` yêu cầu mật khẩu và trả về `root`; `sudo -l` xác nhận quyền `(ALL : ALL) ALL`.

Những điểm cần ghi nhớ:

- Dùng user thường kết hợp `sudo` tuân thủ Least Privilege: hạn chế thiệt hại do thao tác nhầm, tăng khả năng kiểm toán và thu hồi quyền riêng từng người.
- Phải có `-a` khi dùng `usermod -aG`, nếu không các nhóm phụ hiện có sẽ bị ghi đè.
- Quyền `700` cho `.ssh` và `600` cho `authorized_keys`, cùng chủ sở hữu đúng, là điều kiện để `sshd` (StrictModes) chấp nhận đăng nhập bằng khóa.
- Chỉ sao chép `authorized_keys` khi thư mục nguồn có thể chứa private key hoặc file `config`.
- Luôn giữ một phiên root đang mở và kiểm tra bằng một terminal khác trước khi thay đổi cấu hình truy cập (đặc biệt khi tắt đăng nhập root).
- Khi dùng `NOPASSWD`, chỉ áp dụng cho tài khoản tự động hóa, giới hạn lệnh cụ thể và kiểm tra bằng `visudo -cf`.

Script `setup_devops_user.sh` gom toàn bộ các bước trên ở dạng idempotent, có thể chạy lại an toàn trên Droplet mới.
