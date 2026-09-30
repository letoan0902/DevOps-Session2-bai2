#!/usr/bin/env bash
# ==============================================================================
# setup_devops_user.sh
# Bài 2 - Session 02: Khởi tạo user thường `devops`, cấp quyền sudo và
#                     sao chép SSH Key từ root sang devops.
#
# Đặc điểm:
#   - Idempotent: chạy lại nhiều lần vẫn an toàn, không tạo trùng, không ghi đè.
#   - Chỉ sao chép file authorized_keys (không sao chép private key hay config).
#
# Cách dùng (chạy bằng root, trong một terminal tương tác để đặt mật khẩu):
#   bash setup_devops_user.sh            # tạo user mặc định là "devops"
#   bash setup_devops_user.sh devops     # chỉ định tên user tường minh
#
# Biến môi trường tùy chọn:
#   SRC_KEYS=/đường/dẫn/authorized_keys  (mặc định: /root/.ssh/authorized_keys)
# ==============================================================================

set -euo pipefail

USERNAME="${1:-devops}"
SRC_KEYS="${SRC_KEYS:-/root/.ssh/authorized_keys}"
HOME_DIR="/home/${USERNAME}"
SSH_DIR="${HOME_DIR}/.ssh"
DST_KEYS="${SSH_DIR}/authorized_keys"

# ------------------------------------------------------------------------------
# Hàm tiện ích
# ------------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die()  { printf '[LỖI] %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Bước 0: Kiểm tra điều kiện tiên quyết
# ------------------------------------------------------------------------------
[[ ${EUID} -eq 0 ]] || die "Script cần chạy bằng root (hoặc dùng: sudo bash $0)."
[[ -s "${SRC_KEYS}" ]] || die "Không tìm thấy hoặc file rỗng: ${SRC_KEYS}"

# ------------------------------------------------------------------------------
# Bước 1: Tạo user nếu chưa tồn tại
#   adduser tạo home directory, sao chép /etc/skel và hỏi đặt mật khẩu.
#   Mật khẩu là bắt buộc để `sudo` có thể yêu cầu xác thực đúng theo đề bài.
# ------------------------------------------------------------------------------
if id "${USERNAME}" >/dev/null 2>&1; then
    log "User '${USERNAME}' đã tồn tại, bỏ qua bước tạo user."
else
    [[ -t 0 ]] || die "Cần terminal tương tác để nhập mật khẩu cho '${USERNAME}'."
    log "Đang tạo user '${USERNAME}'..."
    adduser --gecos "" "${USERNAME}"
fi

# ------------------------------------------------------------------------------
# Bước 2: Thêm user vào nhóm sudo nếu chưa thuộc nhóm
# ------------------------------------------------------------------------------
current_groups="$(id -nG "${USERNAME}")"
case " ${current_groups} " in
    *" sudo "*)
        log "User '${USERNAME}' đã thuộc nhóm sudo, bỏ qua."
        ;;
    *)
        log "Đang thêm '${USERNAME}' vào nhóm sudo..."
        usermod -aG sudo "${USERNAME}"
        ;;
esac

# ------------------------------------------------------------------------------
# Bước 3: Sao chép authorized_keys sang home của devops
#   Chỉ copy authorized_keys để tránh vô tình đưa private key hoặc file config
#   của root sang user khác. Từng dòng khóa được thêm nếu chưa có (không ghi đè
#   các khóa đã được cấu hình riêng cho devops trước đó).
# ------------------------------------------------------------------------------
log "Đang chuẩn bị thư mục ${SSH_DIR}..."
mkdir -p "${SSH_DIR}"
touch "${DST_KEYS}"

added=0
while IFS= read -r key_line || [[ -n "${key_line}" ]]; do
    # Bỏ qua dòng trống và dòng chú thích
    [[ -z "${key_line}" || "${key_line}" == \#* ]] && continue
    if ! grep -qxF -- "${key_line}" "${DST_KEYS}"; then
        printf '%s\n' "${key_line}" >> "${DST_KEYS}"
        added=$((added + 1))
    fi
done < "${SRC_KEYS}"
log "Đã thêm ${added} khóa mới vào ${DST_KEYS}."

# ------------------------------------------------------------------------------
# Bước 4: Phân quyền chính xác (sshd với StrictModes sẽ từ chối nếu sai)
#   - Chủ sở hữu: devops:devops
#   - Thư mục .ssh : 700 (drwx------)
#   - authorized_keys : 600 (-rw-------)
# ------------------------------------------------------------------------------
log "Đang thiết lập chủ sở hữu và quyền truy cập..."
chown -R "${USERNAME}:${USERNAME}" "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${DST_KEYS}"

# ------------------------------------------------------------------------------
# Bước 5: Kiểm tra kết quả
# ------------------------------------------------------------------------------
log "Kết quả kiểm tra:"
id "${USERNAME}"
getent group sudo
ls -ld "${SSH_DIR}"
ls -la "${SSH_DIR}"
stat -c '%a %U:%G %n' "${HOME_DIR}" "${SSH_DIR}" "${DST_KEYS}"

cat <<MSG

Hoàn tất. Hãy giữ nguyên phiên root hiện tại và mở một terminal MỚI để kiểm tra:
  ssh -i /đường/dẫn/private_key ${USERNAME}@<IP_DROPLET>
  sudo whoami      # yêu cầu mật khẩu, kết quả: root
MSG
