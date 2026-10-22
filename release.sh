#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Orbit 一键 Archive + 导出 .app + 打包 DMG + 移动到桌面
#
# 1) xcodebuild archive 生成 .xcarchive
# 2) 从 .xcarchive 里把 .app 拷出来（等价 Organizer 里的 Copy App）
# 3) hdiutil 做可写 DMG → 挂载 → AppleScript 设置背景和图标位置 → 压缩只读 DMG
# 4) 把最终 DMG 移到桌面
#
# 说明：
# - DMG 背景图默认用「脚本同目录」下 background.jpg
# - 图标默认：左 1/4、右 3/4、y=高度/2（同一中心线）
# ==========================================================

# ---- 你一般只需要改这里（第一次先别改） ----
APP_NAME="${APP_NAME:-Orbit}"         # app 名字（不含 .app）
SCHEME="${SCHEME:-Orbit}"             # Xcode Scheme 名
CONFIGURATION="${CONFIGURATION:-Release}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-${APP_NAME} Installer}"
CLEAN_BUILD_PACKAGING="${CLEAN_BUILD_PACKAGING:-1}"
EXPORT_DSYM="${EXPORT_DSYM:-1}"
DSYM_ROOT="${DSYM_ROOT:-$HOME/Desktop/Orbit_dSYM}"
DSYM_RETENTION_COUNT="${DSYM_RETENTION_COUNT:-10}"
# 付费开发者账号：有该 Team 的 Developer ID 证书时，用 Developer ID 方式导出并公证 DMG。
TEAM_ID="${TEAM_ID:-9A3Z3BZGG8}"
# notarytool 钥匙串配置名（与 Deck 共用）；NOTARIZE=0 跳过公证（仅本机自测）。
NOTARY_PROFILE="${NOTARY_PROFILE:-deck-notary}"
NOTARIZE="${NOTARIZE:-1}"
# Finder 窗口预留边距（点），避免窗口超出屏幕被系统强制缩小
WINDOW_MARGIN="${WINDOW_MARGIN:-80}"
# Finder 的 bounds 算的是整个窗口外框，不是里面那块背景图区域。
FINDER_WINDOW_FRAME_W="${FINDER_WINDOW_FRAME_W:-0}"
FINDER_WINDOW_FRAME_H="${FINDER_WINDOW_FRAME_H:-25}"
# 使用已有 Archive：
# - USE_XCODE_ARCHIVE=1：从 Xcode 默认 Archives 目录选最新
# - ARCHIVE_PATH：指定具体 .xcarchive（优先级最高）
USE_XCODE_ARCHIVE="${USE_XCODE_ARCHIVE:-0}"
XCODE_ARCHIVES_DIR="${XCODE_ARCHIVES_DIR:-$HOME/Library/Developer/Xcode/Archives}"
ARCHIVE_PATH="${ARCHIVE_PATH:-}"

# 背景图：默认脚本同目录 background.jpg
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-$SCRIPT_DIR/background.jpg}"

# Finder 里图标大小（像素）
ICON_SIZE="${ICON_SIZE:-128}"

# DMG 里附带一键安装/修复脚本（默认关闭，需要时再手动开）
ENABLE_INSTALL_HELPERS="${ENABLE_INSTALL_HELPERS:-0}"
HELPER_FOLDER_NAME="${HELPER_FOLDER_NAME:-${APP_NAME} Installer Tools}"
INSTALL_HELPER_NAME="${INSTALL_HELPER_NAME:-install.command}"
HELP_FILE_NAME="${HELP_FILE_NAME:-help.txt}"
REPAIR_HELPER_NAME="${REPAIR_HELPER_NAME:-fix.command}"

# 安装器图标（DMG 卷图标）：
# - 支持 light/dark/auto（auto 按当前系统外观自动选）
# - 默认使用 photos 下的两张 1024 logo
ENABLE_DMG_VOLUME_ICON="${ENABLE_DMG_VOLUME_ICON:-1}"
INSTALLER_ICON_MODE="${INSTALLER_ICON_MODE:-auto}" # auto | light | dark
INSTALLER_ICON_LIGHT="${INSTALLER_ICON_LIGHT:-$SCRIPT_DIR/Orbit/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png}"
INSTALLER_ICON_DARK="${INSTALLER_ICON_DARK:-$SCRIPT_DIR/Orbit/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png}"

# 如果你要手动微调排版，就填这几个（不填则自动算）
# 单位像素：x 向右变大，y 向下变大
APP_ICON_X="${APP_ICON_X:-}"
APP_ICON_Y="${APP_ICON_Y:-}"
APPS_ICON_X="${APPS_ICON_X:-}"
APPS_ICON_Y="${APPS_ICON_Y:-}"
# 主图标中心线 Y（按背景图坐标，距顶部）
# 当前背景图 902x739，对应：距顶部 383 / 距底部 356
MAIN_ROW_CENTER_Y="${MAIN_ROW_CENTER_Y:-383}"
HELPER_FOLDER_X="${HELPER_FOLDER_X:-}"
HELPER_FOLDER_Y="${HELPER_FOLDER_Y:-}"
HELPER_ITEM_Y="${HELPER_ITEM_Y:-95}"
HELPER_INSTALL_X="${HELPER_INSTALL_X:-120}"
HELPER_HELP_X="${HELPER_HELP_X:-250}"
HELPER_FIX_X="${HELPER_FIX_X:-380}"

# 图标纵向上移（只改 Y，不改 X）
MAIN_ROW_SHIFT_UP="${MAIN_ROW_SHIFT_UP:-45}"      # App + Applications
HELPER_ROW_SHIFT_UP="${HELPER_ROW_SHIFT_UP:-280}" # 工具文件夹（上移更多）

VOLUME_ICON_ICNS=""

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

prune_old_dsyms() {
  local dsym_root="$1"
  local keep_count="$2"

  if [[ ! -d "$dsym_root" ]]; then
    return 0
  fi

  if ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
    echo "WARN: DSYM_RETENTION_COUNT 不是有效数字，跳过 dSYM 清理：$keep_count"
    return 0
  fi

  if (( keep_count <= 0 )); then
    echo "WARN: DSYM_RETENTION_COUNT <= 0，跳过 dSYM 清理。"
    return 0
  fi

  local dsym_paths=()
  local total=0
  local remove_count=0
  local idx=0

  while IFS= read -r path; do
    [[ -n "$path" ]] && dsym_paths+=("$path")
  done < <(find "$dsym_root" -maxdepth 1 -mindepth 1 -type d -name "*.dSYM" -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -n \
    | cut -d' ' -f2-)

  total="${#dsym_paths[@]}"
  if (( total <= keep_count )); then
    echo "dSYM 保留检查：当前 ${total} 个，未超过上限 ${keep_count}。"
    return 0
  fi

  remove_count=$((total - keep_count))
  echo "dSYM 保留检查：当前 ${total} 个，超过上限 ${keep_count}，开始删除最老的 ${remove_count} 个。"

  for (( idx=0; idx<remove_count; idx++ )); do
    if [[ -n "${dsym_paths[$idx]:-}" && -d "${dsym_paths[$idx]}" ]]; then
      echo "   - 删除旧 dSYM: ${dsym_paths[$idx]}"
      rm -rf "${dsym_paths[$idx]}"
    fi
  done
}

detect_appearance_mode() {
  case "$INSTALLER_ICON_MODE" in
    dark|DARK) echo "dark"; return 0 ;;
    light|LIGHT) echo "light"; return 0 ;;
  esac

  local style=""
  style="$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)"
  if echo "$style" | grep -qi "dark"; then
    echo "dark"
  else
    echo "light"
  fi
}

build_icns_from_png() {
  local src_png="$1"
  local out_icns="$2"
  local iconset_dir="$BUILD_ROOT/.volume.iconset"
  local size=0
  local retina=0

  rm -rf "$iconset_dir"
  mkdir -p "$iconset_dir"

  for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$src_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    /usr/bin/sips -z "$retina" "$retina" "$src_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
  done

  /usr/bin/iconutil -c icns "$iconset_dir" -o "$out_icns" >/dev/null
}

prepare_volume_icon() {
  if ! is_truthy "$ENABLE_DMG_VOLUME_ICON"; then
    return 0
  fi

  local mode=""
  local selected=""
  local out_icns="$BUILD_ROOT/.VolumeIcon.icns"

  mode="$(detect_appearance_mode)"
  if [[ "$mode" == "dark" && -f "$INSTALLER_ICON_DARK" ]]; then
    selected="$INSTALLER_ICON_DARK"
  fi
  if [[ -z "$selected" && -f "$INSTALLER_ICON_LIGHT" ]]; then
    selected="$INSTALLER_ICON_LIGHT"
  fi
  if [[ -z "$selected" && -f "$INSTALLER_ICON_DARK" ]]; then
    selected="$INSTALLER_ICON_DARK"
  fi

  if [[ -z "$selected" ]]; then
    echo "WARN: 未找到安装器图标资源，跳过 DMG 卷图标设置。"
    echo "      期望文件：$INSTALLER_ICON_LIGHT 或 $INSTALLER_ICON_DARK"
    return 0
  fi

  if build_icns_from_png "$selected" "$out_icns"; then
    VOLUME_ICON_ICNS="$out_icns"
    echo "   - 安装器图标: ${selected} (mode: ${mode})"
  else
    echo "WARN: 生成 .icns 失败，跳过 DMG 卷图标设置。"
  fi
}

mark_custom_icon_flag() {
  local path="$1"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$path" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v xcrun >/dev/null 2>&1; then
    xcrun SetFile -a C "$path" >/dev/null 2>&1 || true
  fi
}

write_install_helpers() {
  local target_dir="$1"
  local app_bundle="$2"
  local app_base="${app_bundle%.app}"
  local helper_dir="$target_dir/$HELPER_FOLDER_NAME"
  local install_path="$helper_dir/$INSTALL_HELPER_NAME"
  local repair_path="$helper_dir/$REPAIR_HELPER_NAME"
  local help_path="$helper_dir/$HELP_FILE_NAME"

  mkdir -p "$helper_dir"

  cat >"$install_path" <<EOF
#!/bin/bash
set -euo pipefail

APP_BUNDLE_NAME="$app_bundle"
APP_DISPLAY_NAME="$app_base"
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
DMG_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"
SOURCE_APP="\$DMG_ROOT/\$APP_BUNDLE_NAME"
DEST_APP="/Applications/\$APP_BUNDLE_NAME"
BACKUP_APP="/Applications/.\${APP_DISPLAY_NAME}.old.\$(date +%s).app"

shell_quote() {
  printf "'%s'" "\$(printf "%s" "\$1" | sed "s/'/'\\\\''/g")"
}

escape_osascript() {
  printf '%s' "\$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
}

run_with_optional_admin() {
  local cmd="\$1"
  if [[ -w "/Applications" ]]; then
    /bin/bash -lc "\$cmd"
  else
    local escaped=""
    escaped="\$(escape_osascript "\$cmd")"
    /usr/bin/osascript -e "do shell script \\"\$escaped\\" with administrator privileges"
  fi
}

wait_for_app_exit() {
  local app_name="\$1"
  local timeout_sec="\${2:-15}"
  local elapsed=0

  /usr/bin/osascript -e "tell application \"\$app_name\" to quit" >/dev/null 2>&1 || true

  while /usr/bin/pgrep -x "\$app_name" >/dev/null 2>&1; do
    if [[ "\$elapsed" -eq 0 ]]; then
      echo "[${app_base} Installer] 检测到 \$app_name 正在运行，等待退出..."
    fi
    /bin/sleep 0.2
    elapsed=\$((elapsed + 1))
    if (( elapsed >= timeout_sec * 5 )); then
      echo "[${app_base} Installer] \$app_name 未及时退出，尝试强制结束..."
      /usr/bin/pkill -x "\$app_name" >/dev/null 2>&1 || true
      /bin/sleep 0.5
      if /usr/bin/pgrep -x "\$app_name" >/dev/null 2>&1; then
        /usr/bin/pkill -9 -x "\$app_name" >/dev/null 2>&1 || true
      fi
      break
    fi
  done
}

echo "[${app_base} Installer] 开始安装 \$APP_DISPLAY_NAME..."
wait_for_app_exit "\$APP_DISPLAY_NAME" 15

if [[ ! -d "\$SOURCE_APP" ]]; then
  echo "[${app_base} Installer] ERROR: 在当前 DMG 里没找到 \$APP_BUNDLE_NAME"
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "\$SOURCE_APP" >/dev/null 2>&1; then
  echo "[${app_base} Installer] ERROR: 安装包签名校验失败，已终止。"
  exit 1
fi

SOURCE_Q="\$(shell_quote "\$SOURCE_APP")"
DEST_Q="\$(shell_quote "\$DEST_APP")"
BACKUP_Q="\$(shell_quote "\$BACKUP_APP")"

INSTALL_CMD="/usr/bin/xattr -r -d com.apple.quarantine \$SOURCE_Q >/dev/null 2>&1 || true; if [ -d \$DEST_Q ]; then /bin/mv \$DEST_Q \$BACKUP_Q; fi; /usr/bin/ditto \$SOURCE_Q \$DEST_Q; /usr/bin/xattr -r -d com.apple.quarantine \$DEST_Q >/dev/null 2>&1 || true"

run_with_optional_admin "\$INSTALL_CMD"

echo "[${app_base} Installer] 已安装到 \$DEST_APP"
echo "[${app_base} Installer] 正在启动..."
/usr/bin/open "\$DEST_APP" || true
echo "[${app_base} Installer] 完成。"
EOF

  cat >"$help_path" <<EOF
==============================
简体中文
==============================
这两个脚本是做什么的：
1. ${INSTALL_HELPER_NAME}
   - 把 ${app_bundle} 安装到 /Applications
   - 自动清理隔离属性（quarantine）
   - 安装完成后自动打开 App
2. ${REPAIR_HELPER_NAME}
   - 仅清理已安装 App 的隔离属性
   - 适合遇到“无法验证开发者”或“已阻止运行”时使用

怎么运行：
1. 打开「${HELPER_FOLDER_NAME}」文件夹
2. 安装请双击 ${INSTALL_HELPER_NAME}
3. 若仍被系统拦截，再双击 ${REPAIR_HELPER_NAME}
4. 若系统弹出权限提示，按提示输入密码并允许执行
5. 推荐使用 ${INSTALL_HELPER_NAME}，而不是 ${REPAIR_HELPER_NAME}

==============================
English
==============================
What these scripts do:
1. ${INSTALL_HELPER_NAME}
   - Installs ${app_bundle} to /Applications
   - Removes quarantine attributes automatically
   - Opens the app after installation
2. ${REPAIR_HELPER_NAME}
   - Only removes quarantine attributes from the installed app
   - Use this if macOS blocks app launch for security checks

How to run:
1. Open the "${HELPER_FOLDER_NAME}" folder
2. For installation, double-click ${INSTALL_HELPER_NAME}
3. If the app is still blocked, double-click ${REPAIR_HELPER_NAME}
4. If macOS asks for permission, allow it and enter your password

==============================
繁體中文
==============================
這兩個腳本的用途：
1. ${INSTALL_HELPER_NAME}
   - 將 ${app_bundle} 安裝到 /Applications
   - 自動清除隔離屬性（quarantine）
   - 安裝後自動打開 App
2. ${REPAIR_HELPER_NAME}
   - 只清除已安裝 App 的隔離屬性
   - 遇到「無法驗證」或「已阻止執行」時可使用

如何執行：
1. 打開「${HELPER_FOLDER_NAME}」資料夾
2. 安裝請雙擊 ${INSTALL_HELPER_NAME}
3. 若仍被系統阻擋，再雙擊 ${REPAIR_HELPER_NAME}
4. 若系統要求權限，請依提示輸入密碼並允許

==============================
Deutsch
==============================
Wofuer sind diese Skripte:
1. ${INSTALL_HELPER_NAME}
   - Installiert ${app_bundle} nach /Applications
   - Entfernt das Quarantaene-Attribut automatisch
   - Oeffnet die App nach der Installation
2. ${REPAIR_HELPER_NAME}
   - Entfernt nur das Quarantaene-Attribut der installierten App
   - Nuetzlich, wenn macOS den Start blockiert

Ausfuehrung:
1. Ordner "${HELPER_FOLDER_NAME}" oeffnen
2. Fuer die Installation ${INSTALL_HELPER_NAME} doppelklicken
3. Wenn die App weiter blockiert ist, ${REPAIR_HELPER_NAME} doppelklicken
4. Falls macOS Berechtigungen verlangt, bestaetigen und Passwort eingeben

==============================
Francais
==============================
A quoi servent ces scripts :
1. ${INSTALL_HELPER_NAME}
   - Installe ${app_bundle} dans /Applications
   - Supprime automatiquement l'attribut de quarantaine
   - Ouvre l'application apres l'installation
2. ${REPAIR_HELPER_NAME}
   - Supprime uniquement l'attribut de quarantaine de l'app deja installee
   - A utiliser si macOS bloque l'ouverture

Comment lancer :
1. Ouvrez le dossier "${HELPER_FOLDER_NAME}"
2. Pour l'installation, double-cliquez ${INSTALL_HELPER_NAME}
3. Si l'app reste bloquee, double-cliquez ${REPAIR_HELPER_NAME}
4. Si macOS demande une autorisation, acceptez et entrez le mot de passe

==============================
한국어
==============================
이 스크립트의 용도:
1. ${INSTALL_HELPER_NAME}
   - ${app_bundle} 를 /Applications 에 설치
   - 격리(quarantine) 속성을 자동으로 제거
   - 설치 후 앱을 자동으로 실행
2. ${REPAIR_HELPER_NAME}
   - 이미 설치된 앱의 격리 속성만 제거
   - macOS 보안 경고로 실행이 막힐 때 사용

실행 방법:
1. "${HELPER_FOLDER_NAME}" 폴더를 엽니다
2. 설치는 ${INSTALL_HELPER_NAME} 를 더블클릭
3. 여전히 차단되면 ${REPAIR_HELPER_NAME} 를 더블클릭
4. 권한 창이 뜨면 허용하고 비밀번호를 입력

==============================
日本語
==============================
この2つのスクリプトの用途:
1. ${INSTALL_HELPER_NAME}
   - ${app_bundle} を /Applications にインストール
   - quarantine 属性を自動で削除
   - インストール後にアプリを自動起動
2. ${REPAIR_HELPER_NAME}
   - インストール済みアプリの quarantine 属性のみ削除
   - macOS のセキュリティ警告で起動できない時に使用

実行方法:
1. "${HELPER_FOLDER_NAME}" フォルダを開く
2. インストールは ${INSTALL_HELPER_NAME} をダブルクリック
3. まだブロックされる場合は ${REPAIR_HELPER_NAME} をダブルクリック
4. 権限確認が出たら許可してパスワードを入力
EOF

cat >"$repair_path" <<EOF
#!/bin/bash
set -euo pipefail

APP_BUNDLE_NAME="$app_bundle"
APP_DISPLAY_NAME="\${APP_BUNDLE_NAME%.app}"
TARGETS=("/Applications/\$APP_BUNDLE_NAME" "\$HOME/Applications/\$APP_BUNDLE_NAME")
FOUND=0

shell_quote() {
  printf "'%s'" "\$(printf "%s" "\$1" | sed "s/'/'\\\\''/g")"
}

escape_osascript() {
  printf '%s' "\$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
}

run_cmd_for_target() {
  local target="\$1"
  local target_q=""
  local cmd=""
  target_q="\$(shell_quote "\$target")"
  cmd="/usr/bin/xattr -r -d com.apple.quarantine \$target_q >/dev/null 2>&1 || true"

  if [[ "\$target" == /Applications/* && ! -w "/Applications" ]]; then
    local escaped=""
    escaped="\$(escape_osascript "\$cmd")"
    /usr/bin/osascript -e "do shell script \\"\$escaped\\" with administrator privileges"
  else
    /bin/bash -lc "\$cmd"
  fi
}

wait_for_app_exit() {
  local app_name="\$1"
  local timeout_sec="\${2:-15}"
  local elapsed=0

  /usr/bin/osascript -e "tell application \"\$app_name\" to quit" >/dev/null 2>&1 || true

  while /usr/bin/pgrep -x "\$app_name" >/dev/null 2>&1; do
    if [[ "\$elapsed" -eq 0 ]]; then
      echo "[${app_base} Repair] 检测到 \$app_name 正在运行，等待退出..."
    fi
    /bin/sleep 0.2
    elapsed=\$((elapsed + 1))
    if (( elapsed >= timeout_sec * 5 )); then
      echo "[${app_base} Repair] \$app_name 未及时退出，尝试强制结束..."
      /usr/bin/pkill -x "\$app_name" >/dev/null 2>&1 || true
      /bin/sleep 0.5
      if /usr/bin/pgrep -x "\$app_name" >/dev/null 2>&1; then
        /usr/bin/pkill -9 -x "\$app_name" >/dev/null 2>&1 || true
      fi
      break
    fi
  done
}

wait_for_app_exit "\$APP_DISPLAY_NAME" 15

for target in "\${TARGETS[@]}"; do
  if [[ -d "\$target" ]]; then
    FOUND=1
    echo "[${app_base} Repair] 清理隔离属性：\$target"
    run_cmd_for_target "\$target"
    /usr/bin/open "\$target" || true
  fi
done

if [[ "\$FOUND" -eq 0 ]]; then
  echo "[${app_base} Repair] 未找到 \${APP_BUNDLE_NAME}（已检查 /Applications 和 ~/Applications）"
  exit 1
fi

echo "[${app_base} Repair] 完成。"
EOF

  chmod +x "$install_path" "$repair_path"
}

# ---- 找工程根目录：从脚本目录开始往上找（最多 5 层）----
find_project_root() {
  local d="$SCRIPT_DIR"
  local i=0
  while [[ $i -lt 5 ]]; do
    if find "$d" -maxdepth 1 -name "*.xcworkspace" -print -quit | grep -q . \
      || find "$d" -maxdepth 1 -name "*.xcodeproj" -print -quit | grep -q .; then
      (cd "$d" && pwd)
      return 0
    fi
    d="$(cd "$d/.." && pwd)"
    i=$((i+1))
  done
  return 1
}

find_latest_xcode_archive() {
  local archives_dir="$1"
  local app_name="$2"
  local latest_match=""
  local latest_match_mtime=0
  local latest_any=""
  local latest_any_mtime=0
  local archive=""
  local mtime=""

  if [[ ! -d "$archives_dir" ]]; then
    return 1
  fi

  while IFS= read -r -d '' archive; do
    mtime="$(stat -f %m "$archive" 2>/dev/null || stat -c %Y "$archive" 2>/dev/null || echo 0)"
    if [[ "$mtime" -gt "$latest_any_mtime" ]]; then
      latest_any_mtime="$mtime"
      latest_any="$archive"
    fi
    if [[ -d "$archive/Products/Applications/${app_name}.app" ]]; then
      if [[ "$mtime" -gt "$latest_match_mtime" ]]; then
        latest_match_mtime="$mtime"
        latest_match="$archive"
      fi
    fi
  done < <(find "$archives_dir" -type d -name "*.xcarchive" -print0 2>/dev/null || true)

  if [[ -n "$latest_match" ]]; then
    echo "$latest_match"
    return 0
  fi
  if [[ -n "$latest_any" ]]; then
    echo "$latest_any"
    return 0
  fi
  return 1
}

get_screen_size() {
  local size=""
  local w=""
  local h=""
  size="$(/usr/bin/osascript <<'OSA' 2>/dev/null || true
tell application "Finder"
  set b to bounds of window of desktop
  return (item 3 of b) & " " & (item 4 of b)
end tell
OSA
  )"
  if [[ -n "$size" ]]; then
    w="$(echo "$size" | awk '{print $1}')"
    h="$(echo "$size" | awk '{print $2}')"
    if [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]]; then
      echo "$w $h"
      return 0
    fi
  fi
  return 1
}

ROOT_DIR="$(find_project_root || true)"
if [[ -z "${ROOT_DIR:-}" ]]; then
  echo "ERROR: 找不到 .xcworkspace 或 .xcodeproj。"
  echo "   解决：把 release.sh 放到工程目录（或工程目录的子目录）再运行。"
  exit 1
fi

# 选择 workspace / project
XCODE_CONTAINER="$(find "$ROOT_DIR" -maxdepth 1 -name "*.xcworkspace" -print -quit || true)"
XCODE_ARGS=()
if [[ -n "$XCODE_CONTAINER" ]]; then
  XCODE_ARGS=(-workspace "$XCODE_CONTAINER")
else
  XCODE_CONTAINER="$(find "$ROOT_DIR" -maxdepth 1 -name "*.xcodeproj" -print -quit || true)"
  if [[ -z "$XCODE_CONTAINER" ]]; then
    echo "ERROR: 工程目录里没有 .xcworkspace 或 .xcodeproj：$ROOT_DIR"
    exit 1
  fi
  XCODE_ARGS=(-project "$XCODE_CONTAINER")
fi

# 检查背景图
if [[ ! -f "$BACKGROUND_IMAGE" ]]; then
  echo "ERROR: 找不到背景图：$BACKGROUND_IMAGE"
  echo "   你需要准备 background.jpg，并放到脚本同目录。"
  exit 1
fi

# 输出目录
BUILD_ROOT="$ROOT_DIR/build_packaging"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
EXPORT_DIR="$BUILD_ROOT/Export"
DMG_STAGING="$BUILD_ROOT/dmg-staging"
DMG_RW="$BUILD_ROOT/${APP_NAME}-rw.dmg"
DMG_FINAL="$BUILD_ROOT/${APP_NAME}.dmg"

ARCHIVE_SOURCE="build"
if [[ -n "$ARCHIVE_PATH" ]]; then
  ARCHIVE_SOURCE="provided"
elif [[ "$USE_XCODE_ARCHIVE" == "1" || "$USE_XCODE_ARCHIVE" == "true" ]]; then
  ARCHIVE_SOURCE="xcode"
  ARCHIVE_PATH="$(find_latest_xcode_archive "$XCODE_ARCHIVES_DIR" "$APP_NAME" || true)"
  if [[ -z "${ARCHIVE_PATH:-}" ]]; then
    echo "ERROR: 在 Xcode Archives 中找不到可用的 .xcarchive：$XCODE_ARCHIVES_DIR"
    echo "   解决：先用 Xcode Organizer Archive 一次，或设置 ARCHIVE_PATH 指定路径。"
    exit 1
  fi
else
  ARCHIVE_PATH="$BUILD_ROOT/${APP_NAME}.xcarchive"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

echo "工程根目录：$ROOT_DIR"
echo "工程文件：$XCODE_CONTAINER"
echo "Scheme：$SCHEME"
echo "DMG 卷名：$DMG_VOLUME_NAME"
echo "Archive：$ARCHIVE_PATH"
echo "背景图：$BACKGROUND_IMAGE"
echo "----------------------------------------"

if [[ "$ARCHIVE_SOURCE" == "build" ]]; then
  echo "1) 开始 Xcode Archive…"
  xcodebuild "${XCODE_ARGS[@]}" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    clean archive \
    SKIP_INSTALL=NO

  echo "Archive 完成：$ARCHIVE_PATH"
else
  echo "1) 使用已有 Archive…"
  if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive 不存在：$ARCHIVE_PATH"
    exit 1
  fi
fi

echo "2) 从 .xcarchive 导出 .app（等价 Copy App）…"
APP_SRC="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_SRC" ]]; then
  APP_SRC="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name "*.app" -print -quit || true)"
fi
if [[ -z "${APP_SRC:-}" || ! -d "$APP_SRC" ]]; then
  echo "ERROR: 在 archive 里没找到 .app：$ARCHIVE_PATH/Products/Applications/"
  exit 1
fi

APP_BUNDLE_NAME="$(basename "$APP_SRC")"
APP_BUNDLE_BASE="${APP_BUNDLE_NAME%.app}"

mkdir -p "$EXPORT_DIR"
DEVELOPER_ID_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
  | /usr/bin/awk -F'"' -v team="(${TEAM_ID})" '/Developer ID Application:/ && index($2, team) {print $2; exit}')"
if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
  # Developer ID 必须走 exportArchive：直接重签 Archive 里的 App 会带着开发描述文件，Gatekeeper 会拒绝。
  EXPORT_OPTIONS_PLIST="$BUILD_ROOT/ExportOptions.plist"
  /usr/bin/plutil -create xml1 "$EXPORT_OPTIONS_PLIST"
  /usr/bin/plutil -insert method -string developer-id "$EXPORT_OPTIONS_PLIST"
  /usr/bin/plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS_PLIST"
  /usr/bin/plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS_PLIST"
  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -exportPath "$EXPORT_DIR" -allowProvisioningUpdates
  echo "已用 Developer ID 导出：$EXPORT_DIR/${APP_BUNDLE_NAME}（${DEVELOPER_ID_IDENTITY}）"
else
  if [[ "$NOTARIZE" == "1" ]]; then
    echo "ERROR: 没找到 Team ${TEAM_ID} 的 Developer ID Application 证书，无法公证；仅本机自测可用 NOTARIZE=0。"
    exit 1
  fi
  ditto "$APP_SRC" "$EXPORT_DIR/$APP_BUNDLE_NAME"
  echo "已导出：$EXPORT_DIR/$APP_BUNDLE_NAME"
fi

if [[ "$EXPORT_DSYM" == "1" || "$EXPORT_DSYM" == "true" ]]; then
  echo "2.5) 导出 dSYM…"
  DSYM_SRC="$ARCHIVE_PATH/dSYMs/${APP_BUNDLE_NAME}.dSYM"
  if [[ ! -d "$DSYM_SRC" ]]; then
    DSYM_SRC="$(find "$ARCHIVE_PATH/dSYMs" -maxdepth 1 -name "*.dSYM" -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "${DSYM_SRC:-}" || ! -d "$DSYM_SRC" ]]; then
    echo "WARN: 未找到 dSYM，跳过导出：$ARCHIVE_PATH/dSYMs"
  else
    APP_VERSION=""
    if [[ -f "$APP_SRC/Contents/Info.plist" ]]; then
      APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist" 2>/dev/null || true)"
      if [[ -z "$APP_VERSION" ]]; then
        APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_SRC/Contents/Info.plist" 2>/dev/null || true)"
      fi
    fi
    if [[ -z "$APP_VERSION" && -f "$ARCHIVE_PATH/Info.plist" ]]; then
      APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
      if [[ -z "$APP_VERSION" ]]; then
        APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
      fi
    fi
    if [[ -z "$APP_VERSION" ]]; then
      echo "ERROR: 无法读取 App 版本，dSYM 需要版本命名。"
      exit 1
    fi

    mkdir -p "$DSYM_ROOT"
    DSYM_DEST="$DSYM_ROOT/${APP_BUNDLE_BASE}-${APP_VERSION}.dSYM"
    rm -rf "$DSYM_DEST"
    ditto "$DSYM_SRC" "$DSYM_DEST"
    echo "已导出 dSYM：$DSYM_DEST"
    prune_old_dsyms "$DSYM_ROOT" "$DSYM_RETENTION_COUNT"
  fi
else
  echo "2.5) 跳过 dSYM 导出（EXPORT_DSYM=${EXPORT_DSYM}）"
fi

echo "2.8) 准备安装器图标…"
prepare_volume_icon

echo "3) 开始制作 DMG（可写→排版→压缩只读）…"

mkdir -p "$DMG_STAGING"
ditto "$EXPORT_DIR/$APP_BUNDLE_NAME" "$DMG_STAGING/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_STAGING/Applications"

INSTALL_HELPERS_ENABLED=0
if is_truthy "$ENABLE_INSTALL_HELPERS"; then
  write_install_helpers "$DMG_STAGING" "$APP_BUNDLE_NAME"
  INSTALL_HELPERS_ENABLED=1
  echo "   - 已生成工具文件夹：$HELPER_FOLDER_NAME"
  echo "     包含：$INSTALL_HELPER_NAME / $REPAIR_HELPER_NAME / $HELP_FILE_NAME"
fi

if [[ -n "${VOLUME_ICON_ICNS:-}" && -f "$VOLUME_ICON_ICNS" ]]; then
  cp "$VOLUME_ICON_ICNS" "$DMG_STAGING/.VolumeIcon.icns"
fi

mkdir -p "$DMG_STAGING/.background"

# 复制背景图，并强制设成 72 DPI（避免 Finder 背景图缩放问题）
#（有系统版本会按 DPI 缩放背景图，这个处理能规避常见坑）
BG_TMP="$BUILD_ROOT/background.jpg"
cp "$BACKGROUND_IMAGE" "$BG_TMP"
/usr/bin/sips -s dpiWidth 72 -s dpiHeight 72 "$BG_TMP" >/dev/null 2>&1 || true

# 读背景图尺寸（用于画布大小和中心线）
BG_W="$(/usr/bin/sips -g pixelWidth "$BG_TMP" 2>/dev/null | awk '/pixelWidth/ {print $2}' || true)"
BG_H="$(/usr/bin/sips -g pixelHeight "$BG_TMP" 2>/dev/null | awk '/pixelHeight/ {print $2}' || true)"
if [[ -z "${BG_W:-}" || -z "${BG_H:-}" ]]; then
  BG_W=640
  BG_H=400
fi

SCREEN_SIZE="$(get_screen_size || true)"
SCREEN_W=""
SCREEN_H=""
if [[ -n "$SCREEN_SIZE" ]]; then
  read -r SCREEN_W SCREEN_H <<<"$SCREEN_SIZE"
fi

if [[ -n "$SCREEN_W" && -n "$SCREEN_H" ]]; then
  MAX_CONTENT_W=$((SCREEN_W - WINDOW_MARGIN * 2 - FINDER_WINDOW_FRAME_W))
  MAX_CONTENT_H=$((SCREEN_H - WINDOW_MARGIN * 2 - FINDER_WINDOW_FRAME_H))
  if (( MAX_CONTENT_W > 0 && MAX_CONTENT_H > 0 )); then
    if (( BG_W > MAX_CONTENT_W || BG_H > MAX_CONTENT_H )); then
      SCALE_INFO="$(awk -v bw="$BG_W" -v bh="$BG_H" -v mw="$MAX_CONTENT_W" -v mh="$MAX_CONTENT_H" 'BEGIN { sw=mw/bw; sh=mh/bh; s=(sw<sh)?sw:sh; if (s>1) s=1; nw=int(bw*s); nh=int(bh*s); if (nw<1) nw=1; if (nh<1) nh=1; printf "%.4f %d %d", s, nw, nh }')"
      read -r BG_SCALE BG_W_NEW BG_H_NEW <<<"$SCALE_INFO"
      if (( BG_W_NEW > 0 && BG_H_NEW > 0 )); then
        /usr/bin/sips -z "$BG_H_NEW" "$BG_W_NEW" "$BG_TMP" >/dev/null 2>&1 || true
        /usr/bin/sips -s dpiWidth 72 -s dpiHeight 72 "$BG_TMP" >/dev/null 2>&1 || true
        BG_W="$BG_W_NEW"
        BG_H="$BG_H_NEW"
        echo "   - 背景图缩放：${BG_W}x${BG_H}（屏幕 ${SCREEN_W}x${SCREEN_H}）"
      fi
    fi
  fi
fi

cp "$BG_TMP" "$DMG_STAGING/.background/background.jpg"

WIN_W=$((BG_W + FINDER_WINDOW_FRAME_W))
WIN_H=$((BG_H + FINDER_WINDOW_FRAME_H))

if [[ -n "$SCREEN_W" && -n "$SCREEN_H" ]]; then
  WIN_LEFT=$(( (SCREEN_W - WIN_W) / 2 ))
  WIN_TOP=$(( (SCREEN_H - WIN_H) / 2 ))
  if (( WIN_LEFT < 0 )); then WIN_LEFT=0; fi
  if (( WIN_TOP < 0 )); then WIN_TOP=0; fi
else
  WIN_LEFT=200
  WIN_TOP=200
fi
WIN_RIGHT=$((WIN_LEFT + WIN_W))
WIN_BOTTOM=$((WIN_TOP + WIN_H))

DEFAULT_Y="$MAIN_ROW_CENTER_Y"
if [[ ! "$DEFAULT_Y" =~ ^[0-9]+$ ]]; then
  DEFAULT_Y=$((BG_H / 2 - MAIN_ROW_SHIFT_UP))
fi
DEFAULT_APP_X=$((BG_W / 4 - 60))
DEFAULT_APPS_X=$((BG_W * 3 / 4 + 40))
if (( DEFAULT_Y < 0 )); then DEFAULT_Y=0; fi
if (( DEFAULT_Y > BG_H )); then DEFAULT_Y=$BG_H; fi
if (( DEFAULT_APP_X < 0 )); then DEFAULT_APP_X=0; fi

APP_X="${APP_ICON_X:-$DEFAULT_APP_X}"
APP_Y="${APP_ICON_Y:-${APPS_ICON_Y:-$DEFAULT_Y}}"
APPS_X="${APPS_ICON_X:-$DEFAULT_APPS_X}"
APPS_Y="$APP_Y"
DEFAULT_HELPER_FOLDER_Y=$((BG_H - HELPER_ROW_SHIFT_UP))
if (( DEFAULT_HELPER_FOLDER_Y < 0 )); then DEFAULT_HELPER_FOLDER_Y=0; fi
HELPER_X="${HELPER_FOLDER_X:-$APPS_X}"
HELPER_Y="${HELPER_FOLDER_Y:-$DEFAULT_HELPER_FOLDER_Y}"
INNER_ITEM_Y="$HELPER_ITEM_Y"
INNER_INSTALL_X="$HELPER_INSTALL_X"
INNER_HELP_X="$HELPER_HELP_X"
INNER_FIX_X="$HELPER_FIX_X"

echo "   - DMG 画布：${BG_W}x${BG_H}"
echo "   - Finder 窗口外框：${WIN_W}x${WIN_H}"
echo "   - 图标位置：${APP_BUNDLE_NAME} @ {${APP_X},${APP_Y}} / Applications @ {${APPS_X},${APPS_Y}}"
if [[ "$INSTALL_HELPERS_ENABLED" == "1" ]]; then
  echo "   - 工具文件夹位置：${HELPER_FOLDER_NAME} @ {${HELPER_X},${HELPER_Y}}"
  echo "   - 工具文件夹内部：${INSTALL_HELPER_NAME} @ {${INNER_INSTALL_X},${INNER_ITEM_Y}} / ${HELP_FILE_NAME} @ {${INNER_HELP_X},${INNER_ITEM_Y}} / ${REPAIR_HELPER_NAME} @ {${INNER_FIX_X},${INNER_ITEM_Y}}"
fi

hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGING" \
  -fs HFS+ \
  -format UDRW \
  -ov "$DMG_RW" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$DMG_RW" -nobrowse -noverify)"
MOUNT_DIR="$(echo "$ATTACH_OUTPUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
if [[ -z "${MOUNT_DIR:-}" ]]; then
  echo "ERROR: 无法解析 DMG 挂载点"
  exit 1
fi
MOUNT_NAME="$(basename "$MOUNT_DIR")"

if [[ ! -f "$MOUNT_DIR/.background/background.jpg" ]]; then
  echo "ERROR: DMG 中缺少背景图：$MOUNT_DIR/.background/background.jpg"
  exit 1
fi

cleanup() {
  set +e
  if [[ -n "${MOUNT_DIR:-}" ]]; then
    hdiutil detach -force "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

detach_dmg_with_retry() {
  local target="$1"
  local max_attempts="${2:-10}"
  local delay_sec="${3:-0.7}"
  local attempt=1

  if [[ -z "${target:-}" ]]; then
    return 0
  fi

  while (( attempt <= max_attempts )); do
    if hdiutil detach "$target" >/dev/null 2>&1; then
      return 0
    fi

    /bin/sleep "$delay_sec"
    attempt=$((attempt + 1))
  done

  echo "WARN: 普通卸载失败，改用强制卸载：$target"
  hdiutil detach -force "$target" >/dev/null 2>&1
}

osascript <<OSA
on run
  set volName to "$MOUNT_NAME"
  set appName to "$APP_BUNDLE_NAME"
  set installHelpersEnabled to "$INSTALL_HELPERS_ENABLED"
  set helperFolderName to "$HELPER_FOLDER_NAME"
  set installHelperName to "$INSTALL_HELPER_NAME"
  set helpFileName to "$HELP_FILE_NAME"
  set repairHelperName to "$REPAIR_HELPER_NAME"
  set bgName to "background.jpg"
  set mountDir to "$MOUNT_DIR"
  set winBounds to {$WIN_LEFT, $WIN_TOP, $WIN_RIGHT, $WIN_BOTTOM}
  set appPos to {$APP_X, $APP_Y}
  set appsPos to {$APPS_X, $APPS_Y}
  set helperFolderPos to {$HELPER_X, $HELPER_Y}
  set installItemPos to {$INNER_INSTALL_X, $INNER_ITEM_Y}
  set helpItemPos to {$INNER_HELP_X, $INNER_ITEM_Y}
  set repairItemPos to {$INNER_FIX_X, $INNER_ITEM_Y}
  set iconSize to $ICON_SIZE

  tell application "Finder"
    repeat 20 times
      if exists disk volName then exit repeat
      delay 0.2
    end repeat
    if not (exists disk volName) then error "Finder can't see disk " & volName

    tell disk volName
      open
      delay 0.5

      set theWindow to container window
      set current view of theWindow to icon view
      set toolbar visible of theWindow to false
      set statusbar visible of theWindow to false
      set bounds of theWindow to winBounds

      set viewOptions to the icon view options of theWindow
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to iconSize
      set text size of viewOptions to 12
      set bgPath to mountDir & "/.background/" & bgName
      set background picture of viewOptions to POSIX file bgPath

      delay 0.5
      try
        set position of item appName of theWindow to appPos
      end try
      try
        set position of item "Applications" of theWindow to appsPos
      end try
      if installHelpersEnabled is "1" then
        try
          set position of item helperFolderName of theWindow to helperFolderPos
        end try
        delay 0.2
        try
          open folder helperFolderName of theWindow
          delay 0.3
          set helperWindow to container window of folder helperFolderName of theWindow
          set current view of helperWindow to icon view
          set helperViewOptions to icon view options of helperWindow
          set arrangement of helperViewOptions to not arranged
          set icon size of helperViewOptions to iconSize
          set text size of helperViewOptions to 12
          delay 0.2
          try
            set position of item installHelperName of helperWindow to installItemPos
          end try
          try
            set position of item helpFileName of helperWindow to helpItemPos
          end try
          try
            set position of item repairHelperName of helperWindow to repairItemPos
          end try
          close helperWindow
        end try
      end if

      close theWindow
      open
      delay 0.5
      update without registering applications
      delay 0.5
    end tell
  end tell
end run
OSA

chflags hidden "$MOUNT_DIR/.background" >/dev/null 2>&1 || true
if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
  chflags hidden "$MOUNT_DIR/.VolumeIcon.icns" >/dev/null 2>&1 || true
  mark_custom_icon_flag "$MOUNT_DIR"
fi

detach_dmg_with_retry "$MOUNT_DIR"
MOUNT_DIR=""
trap - EXIT

hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_RW"

echo "DMG 已生成：$DMG_FINAL"

if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
  echo "3.5) 签名 DMG…"
  /usr/bin/codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG_FINAL"
  if [[ "$NOTARIZE" == "1" ]]; then
    echo "3.6) 公证并 staple DMG（profile: ${NOTARY_PROFILE}）…"
    /usr/bin/xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
    /usr/bin/xcrun stapler staple "$DMG_FINAL"
    /usr/bin/xcrun stapler validate "$DMG_FINAL"
    /usr/sbin/spctl --assess --type open --context context:primary-signature -v "$DMG_FINAL" || true
  fi
fi

echo "4) 移到桌面…"
DESKTOP_PATH="$HOME/Desktop/${APP_NAME}.dmg"
mkdir -p "$HOME/Desktop"
mv -f "$DMG_FINAL" "$DESKTOP_PATH"

if [[ "$CLEAN_BUILD_PACKAGING" == "1" || "$CLEAN_BUILD_PACKAGING" == "true" ]]; then
  if [[ -n "${BUILD_ROOT:-}" && "$BUILD_ROOT" == "$ROOT_DIR/"* ]]; then
    rm -rf "$BUILD_ROOT"
    echo "已清理：$BUILD_ROOT"
  else
    echo "跳过清理：BUILD_ROOT 不安全 ($BUILD_ROOT)"
  fi
fi

echo "完成！你的 DMG 在：$DESKTOP_PATH"
