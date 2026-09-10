#!/bin/bash
# ============================================
# TRASSIR Monitor — Launcher v1.0
# Единая точка входа: установка/обновление/удаление дашборда и
# уведомлений (Telegram/Email), смена пароля администратора.
#
# Не дублирует логику самих установщиков — install-trassir-monitor.sh /
# install-telegram-notifier.sh / install-mail-notifier.sh / их
# анинсталлеры уже умеют всё нужное и уже проверены; этот скрипт только
# определяет, что уже установлено (по факту на диске/в systemd, а не по
# отдельному файлу-флагу — см. CLAUDE.md), и вызывает нужный из них.
#
# Работает и будучи скачанным в одиночку (сам подтягивает недостающие
# install-*.sh с GitHub), и будучи частью полного чекаута репозитория
# (тогда использует соседние файлы без обращения к сети, кроме случая
# "5. Update all", который всегда берёт свежую версию).
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
SELF_INSTALL_PATH="/usr/local/bin/trassir-monitor"
REPO_RAW_BASE="https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите с правами root:${NC}"
    echo -e "  ${YELLOW}sudo bash $(basename "$0")${NC}"
    exit 1
fi

# ============================================
# ОПРЕДЕЛЕНИЕ ТЕКУЩЕГО СОСТОЯНИЯ (по факту, не по флагу)
# ============================================
dashboard_installed() {
    [ -f "$INSTALL_DIR/app/app.py" ] && [ -x "$INSTALL_DIR/venv/bin/python3" ]
}

telegram_installed() {
    [ -f "$INSTALL_DIR/app/tg_bot.py" ] || \
    systemctl list-unit-files 2>/dev/null | grep -q "trassir-tgbot"
}

email_installed() {
    [ -f "$INSTALL_DIR/app/mail_bot.py" ] || \
    systemctl list-unit-files 2>/dev/null | grep -q "trassir-mailbot"
}

_bool() { if "$1" >/dev/null 2>&1; then echo "true"; else echo "false"; fi; }

# Коммит, реально зафиксированный install-*.sh при последней успешной
# установке/обновлении КОНКРЕТНОГО модуля (dashboard/telegram/mail) —
# та же метка, которую с этой же правки читает и сам дашборд в футере
# /settings (см. _read_installed_commit в app.py, CLAUDE.md "Same
# version/commit footer..."). Это НЕ то же самое, что _LOCAL_COMMIT
# ниже (тот — про сам файл лаунчера, если он лежит в git-чекауте) —
# этот отвечает на другой вопрос: "какой коммит реально стоит на
# сервере для этого модуля", и именно это спрашивали, когда дашборд
# показывал "коммит: ?" даже после обновления — раньше эта метка
# нигде не сохранялась вообще, теперь install-*.sh пишет её в конце
# каждого успешного прогона.
_read_installed_commit() {
    local module="$1" path="$INSTALL_DIR/data/.installed_commit_$module"
    if [ -f "$path" ]; then
        cat "$path" 2>/dev/null || echo "?"
    else
        echo "?"
    fi
}

_press_enter() {
    echo ""
    read -p "Press Enter to return to the menu... " _dummy
}

# ============================================
# ПОЛУЧЕНИЕ НУЖНОГО install-*.sh / uninstall-*.sh
# ============================================
# force_fresh=0 (по умолчанию): берём соседний файл рядом с этим
# лаунчером, если он есть — без обращения к сети вообще. force_fresh=1
# (используется в "5. Update all"): всегда качаем свежую версию с
# GitHub, соседний файл в этом случае игнорируется намеренно — весь
# смысл обновления в том, чтобы получить актуальный код, а не тот, что
# случайно лежит рядом с лаунчером с момента его собственного скачивания.
#
# Возвращает путь через stdout. Специально НЕ сигнализирует
# "скачан временный / это локальный файл" через отдельную глобальную
# переменную — вызывается через command substitution ($(...)), которая
# всегда выполняется в подпроцессе, так что любое присваивание
# переменной внутри этой функции туда же и пропадает при возврате в
# вызывающий код. _run_installer() ниже поэтому решает, удалять ли
# результат, сравнивая сам путь с $SCRIPT_DIR/$name — а не полагаясь на
# такой флаг.
_get_script() {
    local name="$1" force_fresh="${2:-0}"
    local local_path="$SCRIPT_DIR/$name"

    if [ "$force_fresh" -eq 0 ] && [ -s "$local_path" ]; then
        printf '%s' "$local_path"
        return 0
    fi

    local tmp_path
    tmp_path=$(mktemp --suffix=".sh")
    echo -e "${CYAN}  Fetching $name from GitHub (main, latest)...${NC}" >&2
    if curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 \
         -o "$tmp_path" "$REPO_RAW_BASE/$name" && [ -s "$tmp_path" ]; then
        printf '%s' "$tmp_path"
        return 0
    fi

    rm -f "$tmp_path"
    if [ -s "$local_path" ]; then
        echo -e "${YELLOW}  Could not download $name (no internet?) — using local copy: $local_path${NC}" >&2
        printf '%s' "$local_path"
        return 0
    fi

    echo -e "${RED}  ERROR: could not obtain $name — no internet, and no local copy${NC}" >&2
    echo -e "${RED}  next to this launcher ($SCRIPT_DIR/$name).${NC}" >&2
    return 1
}

_run_installer() {
    local name="$1" force_fresh="${2:-0}" path rc
    path=$(_get_script "$name" "$force_fresh") || return 1
    bash "$path"
    rc=$?
    # Удаляем только если это реально временный файл, скачанный только
    # что — никогда не трогаем соседний файл рядом с лаунчером.
    if [ "$path" != "$SCRIPT_DIR/$name" ]; then
        rm -f "$path"
    fi
    return $rc
}

# ============================================
# ПУНКТ 1 — DASHBOARD
# ============================================
do_install_dashboard() {
    if dashboard_installed; then
        echo -e "${YELLOW}Dashboard is already installed.${NC}"
        read -p "Reinstall / refresh it anyway? (y/N): " ans
        [[ "$ans" =~ ^[Yy]$ ]] || return 0
    fi

    _run_installer "install-trassir-monitor.sh"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo -e "${RED}Dashboard install failed (exit code $rc).${NC}"
        _press_enter
        return 1
    fi

    echo ""
    echo -e "${GREEN}Dashboard step complete.${NC}"

    # По запросу: после установки дашборда сразу предложить уведомления,
    # а не заставлять возвращаться в меню и выбирать пункты 2/3 отдельно.
    if ! telegram_installed; then
        echo ""
        read -p "Install Telegram notifications now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            _run_installer "install-telegram-notifier.sh"
        fi
    fi
    if ! email_installed; then
        echo ""
        read -p "Install Email notifications now? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            _run_installer "install-mail-notifier.sh"
        fi
    fi
    _press_enter
}

# ============================================
# ПУНКТЫ 2/3 — УВЕДОМЛЕНИЯ ПО ОТДЕЛЬНОСТИ
# ============================================
_require_dashboard() {
    if dashboard_installed; then
        return 0
    fi
    echo -e "${RED}Dashboard is not installed yet.${NC}"
    echo -e "${YELLOW}Install it first: menu item 1.${NC}"
    _press_enter
    return 1
}

do_install_email() {
    _require_dashboard || return 1
    if email_installed; then
        echo -e "${YELLOW}Email notifications are already installed.${NC}"
        read -p "Reinstall / refresh anyway? (y/N): " ans
        [[ "$ans" =~ ^[Yy]$ ]] || return 0
    fi
    _run_installer "install-mail-notifier.sh"
    _press_enter
}

do_install_telegram() {
    _require_dashboard || return 1
    if telegram_installed; then
        echo -e "${YELLOW}Telegram notifications are already installed.${NC}"
        read -p "Reinstall / refresh anyway? (y/N): " ans
        [[ "$ans" =~ ^[Yy]$ ]] || return 0
    fi
    _run_installer "install-telegram-notifier.sh"
    _press_enter
}

# ============================================
# ПУНКТ 4 — СМЕНА ПАРОЛЯ АДМИНИСТРАТОРА
# ============================================
do_change_password() {
    _require_dashboard || return 1
    if command -v trassir-monitor-set-password >/dev/null 2>&1; then
        trassir-monitor-set-password
    else
        echo -e "${YELLOW}The 'trassir-monitor-set-password' command was not found${NC}"
        echo -e "${YELLOW}(this install predates it). Run '5. Update all' first, then retry.${NC}"
    fi
    _press_enter
}

# ============================================
# ПУНКТ 5 — ОБНОВИТЬ ВСЁ
# ============================================
do_update_all() {
    if ! dashboard_installed && ! telegram_installed && ! email_installed; then
        echo -e "${YELLOW}Nothing is installed yet — nothing to update.${NC}"
        _press_enter
        return 0
    fi

    echo -e "${CYAN}This re-runs the installer(s) for every component that is currently${NC}"
    echo -e "${CYAN}installed, fetching the latest version of each from GitHub.${NC}"
    echo -e "${GREEN}Dashboard update is safe and non-destructive — the database, all${NC}"
    echo -e "${GREEN}settings, and the admin password are preserved automatically.${NC}"
    if telegram_installed || email_installed; then
        echo -e "${YELLOW}Note: Telegram/Email notifier updates will ask you to re-enter${NC}"
        echo -e "${YELLOW}their credentials (bot token / chat IDs / SMTP login) — have them${NC}"
        echo -e "${YELLOW}ready before continuing.${NC}"
    fi
    echo ""
    read -p "Continue? (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0

    if dashboard_installed; then
        echo ""
        echo -e "${CYAN}=== Updating Dashboard ===${NC}"
        _run_installer "install-trassir-monitor.sh" 1
    fi
    if telegram_installed; then
        echo ""
        echo -e "${CYAN}=== Updating Telegram notifications ===${NC}"
        _run_installer "install-telegram-notifier.sh" 1
    fi
    if email_installed; then
        echo ""
        echo -e "${CYAN}=== Updating Email notifications ===${NC}"
        _run_installer "install-mail-notifier.sh" 1
    fi

    echo ""
    echo -e "${GREEN}Update pass complete.${NC}"
    _press_enter
}

# ============================================
# ПУНКТ 6 — UNINSTALL
# ============================================
do_uninstall() {
    clear
    echo -e "${BOLD}TRASSIR-Monitor — Uninstall${NC}"
    echo ""
    echo "1.  Uninstall Dashboard (Telegram/Email are removed with it — they depend on it)"
    echo "2.  Uninstall Telegram notifications only"
    echo "3.  Uninstall Email notifications only"
    echo "4.  Uninstall everything"
    echo ""
    echo "0.  Back"
    echo ""
    read -p "Choice: " choice

    # Пункты 1-4 НЕ проверяют dashboard_installed()/telegram_installed()/
    # email_installed() перед запуском — раньше проверяли, и это была
    # прямая причина живого бага 2026-09-07: dashboard_installed() (для
    # решения "предлагать ли переустановку/зависимые уведомления")
    # специально строгий — требует ОДНОВРЕМЕННО app.py И исполняемый
    # venv/bin/python3 — а uninstall-trassir-monitor.sh проверял по-
    # другому и по более узкому набору признаков. На сервере с хвостами
    # от старой/частично обновлённой установки эти два расходились: один
    # говорил "установлен", другой в ответ на реальную попытку удаления —
    # "не обнаружен", и мусор так и оставался на диске. Вместо синхронизации
    # двух независимых проверок каждый пункт теперь просто передаёт решение
    # единственному месту, которое его принимает — самому uninstall-*.sh
    # скрипту (его собственная проверка расширена ловить и частичные
    # хвосты, см. его же комментарий) — оно единственное присутствует и в
    # выводе "ничего не найдено", и в реальном удалении.
    case "$choice" in
        1)
            # uninstall-trassir-monitor.sh уже само обнаруживает и снимает
            # Telegram/Email вместе с дашбордом (без него они всё равно
            # не работают) — отдельно вызывать uninstall-telegram-bot.sh/
            # uninstall-mail-notifier.sh здесь не нужно.
            _run_installer "uninstall-trassir-monitor.sh"
            ;;
        2)
            _run_installer "uninstall-telegram-bot.sh"
            ;;
        3)
            _run_installer "uninstall-mail-notifier.sh"
            ;;
        4)
            # Уведомления снимаем ДО дашборда через их собственные
            # анинсталляторы (более подробные вопросы про очистку БД:
            # telegram_logs/mail_logs/telegram_chats/mail_recipients) —
            # к моменту вызова uninstall-trassir-monitor.sh они уже не
            # обнаружатся и не потребуют повторного подтверждения на них.
            # Каждый скрипт сам молча ничего не делает, если ему нечего
            # удалять — три "не обнаружено" подряд на пустой системе это
            # ожидаемый, а не ошибочный вывод.
            _run_installer "uninstall-telegram-bot.sh"
            _run_installer "uninstall-mail-notifier.sh"
            _run_installer "uninstall-trassir-monitor.sh"
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
    _press_enter
}

# ============================================
# УСТАНОВКА СЕБЯ КАК ГЛОБАЛЬНОЙ КОМАНДЫ (удобство, не обязательно)
# ============================================
# Тихо, без вопросов — просто чтобы после первого запуска через
# wget+bash это меню было доступно короткой командой `sudo
# trassir-monitor`, без необходимости помнить, куда скачался сам файл.
_self_install() {
    local self_path
    self_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    [ "$self_path" = "$SELF_INSTALL_PATH" ] && return 0
    if ! cmp -s "$self_path" "$SELF_INSTALL_PATH" 2>/dev/null; then
        cp -f "$self_path" "$SELF_INSTALL_PATH" 2>/dev/null && \
        chmod +x "$SELF_INSTALL_PATH" 2>/dev/null
    fi
}
_self_install

# Дата изменения ЭТОГО файла на диске — прямой ответ на живой баг
# 2026-09-07: "wget без -O" на повторной закачке сохранял новый файл как
# launcher-trassir-monitor.sh.1, не трогая старый, и человек незаметно
# для себя продолжал запускать давно устаревшую копию, гоняясь за
# "исправлениями", которые физически не могли до него доехать. README
# теперь везде использует -O (чинит саму причину), но эта дата в шапке
# меню — подстраховка на будущее: если она выглядит подозрительно
# старой сразу после свежего скачивания, значит запущен не тот файл.
_SELF_MTIME=$(date -r "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "?")

# Короткий хеш текущего коммита — работает только если лаунчер запущен
# из настоящего git-чекаута этого репозитория ($SCRIPT_DIR/.git
# существует), то есть человек склонировал весь репозиторий, а не
# просто скачал один файл через wget (обычный способ распространения
# этого проекта, см. README). Ни этот файл, ни $INSTALL_DIR на реальном
# сервере никогда не бывают git-чекаутом — установщики просто пишут
# сгенерированные файлы на диск, .git там взяться неоткуда (см. "Editing
# means editing the heredoc directly" в CLAUDE.md) — так что честный "?"
# в этом обычном случае ожидаем, а не баг, и не повод подделывать номер
# версии откуда-то ещё.
_git_short_commit() {
    local dir="$1"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?"
    else
        echo "?"
    fi
}
_LOCAL_COMMIT=$(_git_short_commit "$SCRIPT_DIR")

# ============================================
# ГЛАВНОЕ МЕНЮ
# ============================================
# Печатает одну строку пункта 1/2/3: [true/false] + название, и если
# модуль установлен — реальный установленный коммит рядом (см.
# _read_installed_commit выше). Ничего не показывает про коммит для
# неустановленного модуля — "?" рядом с [false] был бы шумом, а не
# информацией.
_module_line() {
    local num="$1" check_fn="$2" label="$3" module="$4" status
    if "$check_fn" >/dev/null 2>&1; then
        printf "%-3s [%-5s] %s (коммит: %s)\n" "$num" "true" "$label" "$(_read_installed_commit "$module")"
    else
        printf "%-3s [%-5s] %s\n" "$num" "false" "$label"
    fi
}

show_menu() {
    clear
    echo -e "${GREEN}${BOLD}TRASSIR-Monitor v13.0${NC} ${CYAN}(файл от: ${_SELF_MTIME}, коммит: ${_LOCAL_COMMIT})${NC}"
    echo ""
    _module_line "1." dashboard_installed "Install Dashboard" "dashboard"
    _module_line "2." email_installed "Install Email notification" "mail"
    _module_line "3." telegram_installed "Install Telegram notification" "telegram"
    echo ""
    echo "4.  Change admin passwd"
    echo ""
    echo "5.  Update all"
    echo "6.  Uninstall"
    echo ""
    echo "0.  Exit"
    echo ""
}

while true; do
    show_menu
    read -p "Choice: " CHOICE
    case "$CHOICE" in
        1) do_install_dashboard ;;
        2) do_install_email ;;
        3) do_install_telegram ;;
        4) do_change_password ;;
        5) do_update_all ;;
        6) do_uninstall ;;
        0) echo "Bye."; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
done
