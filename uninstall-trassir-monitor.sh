#!/bin/bash
# ============================================
# Удаление TRASSIR Monitor (основной дашборд)
# ============================================
# В отличие от uninstall-telegram-bot.sh / uninstall-mail-notifier.sh,
# этот скрипт удаляет саму папку проекта ($INSTALL_DIR) целиком —
# включая БД. Telegram/Email нотифайеры без дашборда (venv, app.py,
# БД) всё равно работать не могут, поэтому если они установлены —
# удаляются вместе с ним, а не остаются сиротами с systemd-юнитом,
# указывающим на уже стёртый venv.
#
# Это тот же самый вариант удаления, что генерируется во время установки
# как команда `trassir-monitor-uninstall` (см. install-trassir-monitor.sh,
# секция создания /usr/local/bin/trassir-monitor-uninstall) — держать оба
# места идентичными по логике, если один из них меняется, см. CLAUDE.md.
# Отдельный файл в репозитории нужен для симметрии с двумя другими
# анинсталляторами (можно скачать и запустить сразу одной командой, не
# заходя на уже установленный сервер за готовой командой) и как более
# надёжный путь для launcher-trassir-monitor.sh — он не зависит от того,
# существует ли на сервере ранее сгенерированная команда, была ли она
# создана исполняемой, и не устарела ли она.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
LOG_DIR="$INSTALL_DIR/logs"
DB_PATH="$INSTALL_DIR/data/trassir.db"

clear

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}║   Удаление TRASSIR Monitor                   ║${NC}"
echo -e "${RED}║   (основной дашборд)                         ║${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash uninstall-trassir-monitor.sh${NC}"
    exit 1
fi

# ============================================
# ОПРЕДЕЛЯЕМ ЧТО УСТАНОВЛЕНО
# ============================================
# Намеренно широкая проверка "по ЛЮБОМУ следу", а не только по "полному
# рабочему комплекту" (app.py + venv) — живой баг 2026-09-07: после
# частично неудачного/устаревшего обновления или ручной чистки на диске
# мог остаться, например, systemd-юнит без $INSTALL_DIR, или сама папка
# без app.py, или конфиг nginx без сервиса. Узкая проверка "всё сразу или
# ничего" в таком случае говорила "не обнаружен" и молча оставляла эти
# хвосты нетронутыми — а другой код в проекте (например, launcher'а
# собственный dashboard_installed(), который целенаправленно строже,
# см. его комментарий) мог в этот же момент сообщать "установлен",
# опираясь на другой конкретный файл. Здесь любой ОДИН найденный след —
# уже достаточное основание предложить полную чистку; сами шаги удаления
# ниже и так написаны терпимо к недостающим целям (rm -f, systemctl ...
# || true), так что прогнать их по частично-пустому состоянию безопасно.
HAS_DASHBOARD=0
[ -d "$INSTALL_DIR" ] && HAS_DASHBOARD=1
[ -f "$INSTALL_DIR/app/app.py" ] && HAS_DASHBOARD=1
[ -f "/etc/systemd/system/trassir-monitor.service" ] && HAS_DASHBOARD=1
systemctl list-unit-files 2>/dev/null | grep -q "^trassir-monitor\.service" && HAS_DASHBOARD=1
[ -f "/etc/nginx/sites-available/trassir-monitor" ] && HAS_DASHBOARD=1
[ -f "/etc/nginx/sites-enabled/trassir-monitor" ] && HAS_DASHBOARD=1
[ -e /usr/local/bin/trassir-monitor-uninstall ] && HAS_DASHBOARD=1
[ -e /usr/local/bin/trassir-monitor-set-password ] && HAS_DASHBOARD=1

if [ $HAS_DASHBOARD -eq 0 ]; then
    echo -e "${YELLOW}⚠ TRASSIR Monitor не обнаружен.${NC}"
    echo ""
    echo "Проверено:"
    echo "  • Каталог $INSTALL_DIR"
    echo "  • $INSTALL_DIR/app/app.py"
    echo "  • Сервис trassir-monitor (systemd-юнит и файл)"
    echo "  • Конфиги nginx (sites-available/sites-enabled)"
    echo "  • /usr/local/bin/trassir-monitor-uninstall"
    echo "  • /usr/local/bin/trassir-monitor-set-password"
    exit 0
fi

HAS_TGBOT=0
HAS_MAIL=0
systemctl list-unit-files 2>/dev/null | grep -q "trassir-tgbot" && HAS_TGBOT=1
systemctl list-unit-files 2>/dev/null | grep -q "trassir-mailbot" && HAS_MAIL=1
[ -f "/etc/systemd/system/trassir-tgbot.service" ] && HAS_TGBOT=1
[ -f "/etc/systemd/system/trassir-mailbot.service" ] && HAS_MAIL=1
[ -f "$INSTALL_DIR/app/tg_bot.py" ] && HAS_TGBOT=1
[ -f "$INSTALL_DIR/app/mail_bot.py" ] && HAS_MAIL=1

# ============================================
# ПОКАЗЫВАЕМ ЧТО БУДЕТ УДАЛЕНО
# ============================================
echo -e "${BOLD}Обнаружено:${NC}"
echo ""
echo -e "  ${CYAN}Основной дашборд (trassir-monitor)${NC}"
[ $HAS_TGBOT -eq 1 ] && echo -e "  ${CYAN}Telegram-уведомления (trassir-tgbot)${NC}"
[ $HAS_MAIL -eq 1 ]  && echo -e "  ${CYAN}Email-уведомления (trassir-mailbot)${NC}"
echo ""

if [ $HAS_TGBOT -eq 1 ] || [ $HAS_MAIL -eq 1 ]; then
    echo -e "${YELLOW}Внимание: без дашборда (venv, app.py, БД) Telegram/Email${NC}"
    echo -e "${YELLOW}уведомления всё равно работать не могут — они будут удалены${NC}"
    echo -e "${YELLOW}вместе с ним, чтобы не оставлять сломанные systemd-юниты.${NC}"
    echo ""
fi

echo "Будет удалено:"
echo "  • $INSTALL_DIR (папка проекта целиком, включая базу данных)"
echo "  • /etc/systemd/system/trassir-monitor.service"
[ $HAS_TGBOT -eq 1 ] && echo "  • /etc/systemd/system/trassir-tgbot.service"
[ $HAS_MAIL -eq 1 ]  && echo "  • /etc/systemd/system/trassir-mailbot.service"
echo "  • /etc/nginx/sites-available/trassir-monitor"
echo "  • /etc/nginx/sites-enabled/trassir-monitor"
echo "  • /usr/local/bin/trassir-monitor-uninstall"
echo "  • /usr/local/bin/trassir-monitor-set-password"
echo ""
echo -e "${GREEN}НЕ будет удалено:${NC}"
echo "  • Python, pip, Nginx (сами пакеты)"
echo "  • Другие проекты на этом сервере"
echo ""

# ============================================
# СОХРАНИТЬ ДАННЫЕ?
# ============================================
read -p "Сохранить базу данных и логи перед удалением? (y/N): " SAVE_DATA

if [[ $SAVE_DATA =~ ^[Yy]$ ]]; then
    BACKUP_DIR="/root/trassir-monitor-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [ -d "$INSTALL_DIR/data" ] && cp -r "$INSTALL_DIR/data" "$BACKUP_DIR/" 2>/dev/null && echo "  ✓ data/ (БД, ключ сессии) сохранена"
    [ -d "$LOG_DIR" ]          && cp -r "$LOG_DIR" "$BACKUP_DIR/" 2>/dev/null          && echo "  ✓ logs/ сохранены"
    [ -f "$INSTALL_DIR/config.ini" ] && cp "$INSTALL_DIR/config.ini" "$BACKUP_DIR/" 2>/dev/null && echo "  ✓ config.ini (Telegram) сохранён"
    echo -e "  ${GREEN}Бэкап: $BACKUP_DIR${NC}"
fi

# ============================================
# ПОДТВЕРЖДЕНИЕ
# ============================================
echo ""
echo -e "${YELLOW}Для подтверждения введите DELETE заглавными буквами:${NC}"
read -p "> " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${GREEN}Отмена удаления.${NC}"
    exit 0
fi

echo ""

# ============================================
# ОСТАНАВЛИВАЕМ СЕРВИСЫ
# ============================================
echo -e "${YELLOW}Остановка сервисов...${NC}"
for svc in trassir-monitor trassir-tgbot trassir-mailbot; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc"
        echo "  ✓ $svc остановлен"
    fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable "$svc"
        echo "  ✓ $svc: автозапуск отключён"
    fi
done

# ============================================
# УДАЛЯЕМ КОНФИГИ
# ============================================
echo -e "${YELLOW}Удаление конфигурационных файлов...${NC}"
rm -f /etc/systemd/system/trassir-monitor.service
rm -f /etc/systemd/system/trassir-tgbot.service
rm -f /etc/systemd/system/trassir-mailbot.service
rm -f /etc/nginx/sites-enabled/trassir-monitor
rm -f /etc/nginx/sites-available/trassir-monitor
rm -f /etc/systemd/system/nginx.service.d/restart-on-network.conf
rmdir /etc/systemd/system/nginx.service.d 2>/dev/null || true

systemctl daemon-reload
systemctl restart nginx 2>/dev/null || /usr/sbin/nginx -s reload 2>/dev/null || true
echo "  ✓ Конфиги удалены"

# ============================================
# УДАЛЯЕМ ПАПКУ ПРОЕКТА
# ============================================
echo -e "${YELLOW}Удаление папки проекта...${NC}"
rm -rf "$INSTALL_DIR"
echo "  ✓ $INSTALL_DIR удалён"

# ============================================
# УДАЛЯЕМ СЛУЖЕБНЫЕ КОМАНДЫ
# ============================================
echo -e "${YELLOW}Удаление служебных команд...${NC}"
rm -f /usr/local/bin/trassir-monitor-uninstall
rm -f /usr/local/bin/trassir-monitor-set-password
echo "  ✓ trassir-monitor-uninstall, trassir-monitor-set-password удалены"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   TRASSIR Monitor полностью удалён!          ║${NC}"
echo -e "${GREEN}║   Системные пакеты сохранены.                ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
