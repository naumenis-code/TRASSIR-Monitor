#!/bin/bash
# ============================================
# Удаление Mail нотифайера TRASSIR Monitor
# ============================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
LOG_DIR="$INSTALL_DIR/logs"
SERVICE_MAIL="trassir-mailbot"
DB_PATH="$INSTALL_DIR/data/trassir.db"

clear

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}║   Удаление Mail нотифайера                   ║${NC}"
echo -e "${RED}║   TRASSIR Monitor                            ║${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash uninstall-mail-notifier.sh${NC}"
    exit 1
fi

# ============================================
# ОПРЕДЕЛЯЕМ ЧТО УСТАНОВЛЕНО
# ============================================
HAS_MAIL=0

systemctl list-unit-files 2>/dev/null | grep -q "trassir-mailbot" && HAS_MAIL=1
[ -f "$INSTALL_DIR/app/mail_bot.py" ] && HAS_MAIL=1

if [ $HAS_MAIL -eq 0 ]; then
    echo -e "${YELLOW}⚠ Mail нотифайер не обнаружен.${NC}"
    echo ""
    echo "Проверено:"
    echo "  • Сервис trassir-mailbot"
    echo "  • $INSTALL_DIR/app/mail_bot.py"
    exit 0
fi

# ============================================
# ПОКАЗЫВАЕМ ЧТО БУДЕТ УДАЛЕНО
# ============================================
echo -e "${BOLD}Будет удалено:${NC}"
echo ""
echo -e "  ${CYAN}Mail нотифайер (trassir-mailbot):${NC}"
[ -f "/etc/systemd/system/trassir-mailbot.service" ] && echo "    • /etc/systemd/system/trassir-mailbot.service"
[ -f "$INSTALL_DIR/app/mail_bot.py" ]                && echo "    • $INSTALL_DIR/app/mail_bot.py"
[ -f "$LOG_DIR/mailbot.log" ]                         && echo "    • $LOG_DIR/mailbot.log"
[ -f "$LOG_DIR/mailbot-error.log" ]                   && echo "    • $LOG_DIR/mailbot-error.log"
echo ""
echo -e "${GREEN}НЕ будет удалено:${NC}"
echo "  • База данных (trassir.db)"
echo "  • Основной монитор (trassir-monitor)"
echo "  • Telegram нотифайер (если установлен)"
echo "  • Настройки SMTP в БД (mail_settings)"
echo "  • Список получателей в БД (mail_recipients)"
echo ""

# ============================================
# СОХРАНИТЬ ЛОГИ?
# ============================================
read -p "Сохранить логи перед удалением? (y/N): " SAVE_LOGS

if [[ $SAVE_LOGS =~ ^[Yy]$ ]]; then
    BACKUP_DIR="/root/trassir-mailbot-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [ -f "$LOG_DIR/mailbot.log" ]       && cp "$LOG_DIR/mailbot.log" "$BACKUP_DIR/"       && echo "  ✓ mailbot.log сохранён"
    [ -f "$LOG_DIR/mailbot-error.log" ] && cp "$LOG_DIR/mailbot-error.log" "$BACKUP_DIR/" && echo "  ✓ mailbot-error.log сохранён"
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
# ОСТАНАВЛИВАЕМ И УДАЛЯЕМ СЕРВИС
# ============================================
echo -e "${YELLOW}Удаление trassir-mailbot...${NC}"

if systemctl is-active --quiet $SERVICE_MAIL 2>/dev/null; then
    systemctl stop $SERVICE_MAIL
    echo "  ✓ Сервис остановлен"
fi
if systemctl is-enabled --quiet $SERVICE_MAIL 2>/dev/null; then
    systemctl disable $SERVICE_MAIL
    echo "  ✓ Автозапуск отключён"
fi

rm -f /etc/systemd/system/$SERVICE_MAIL.service
rm -f "$INSTALL_DIR/app/mail_bot.py"
rm -f "$LOG_DIR/mailbot.log"
rm -f "$LOG_DIR/mailbot-error.log"

echo -e "  ${GREEN}✓ trassir-mailbot удалён${NC}"

# ============================================
# ОЧИСТКА ДАННЫХ В БД (опционально)
# ============================================
if [ -f "$DB_PATH" ]; then
    echo ""
    read -p "Удалить историю отправок (mail_logs) из БД? (y/N): " CLEAN_LOGS
    if [[ $CLEAN_LOGS =~ ^[Yy]$ ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM mail_logs;" 2>/dev/null && \
            echo -e "  ${GREEN}✓ mail_logs очищена${NC}" || \
            echo -e "  ${YELLOW}⚠ Не удалось очистить mail_logs${NC}"
    fi

    read -p "Удалить получателей (mail_recipients) и настройки SMTP (mail_settings)? (y/N): " CLEAN_SETTINGS
    if [[ $CLEAN_SETTINGS =~ ^[Yy]$ ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM mail_recipients;" 2>/dev/null && \
            echo -e "  ${GREEN}✓ mail_recipients очищена${NC}"
        sqlite3 "$DB_PATH" "DELETE FROM mail_settings;" 2>/dev/null && \
            echo -e "  ${GREEN}✓ mail_settings очищена${NC}"
    fi
fi

# ============================================
# ПЕРЕЗАГРУЖАЕМ SYSTEMD
# ============================================
systemctl daemon-reload
echo ""

# ============================================
# ИТОГ
# ============================================
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Mail нотифайер удалён!                     ║${NC}"
echo -e "${GREEN}║   Основной монитор продолжает работать.      ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if systemctl is-active --quiet trassir-monitor 2>/dev/null; then
    echo -e "  ${GREEN}✓ trassir-monitor работает${NC}"
else
    echo -e "  ${YELLOW}⚠ trassir-monitor не запущен${NC}"
    echo -e "     Запустить: ${CYAN}systemctl start trassir-monitor${NC}"
fi
echo ""
