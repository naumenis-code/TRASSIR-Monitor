#!/bin/bash
# ============================================
# Удаление Telegram нотифайера TRASSIR Monitor
# Поддерживает: trassir-tgbot и trassir-tgproxy
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

clear

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}║   Удаление Telegram нотифайера               ║${NC}"
echo -e "${RED}║   TRASSIR Monitor                            ║${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash uninstall-telegram-notifier.sh${NC}"
    exit 1
fi

# ============================================
# ОПРЕДЕЛЯЕМ ЧТО УСТАНОВЛЕНО
# ============================================
HAS_TGBOT=0
HAS_TGPROXY=0

systemctl list-unit-files 2>/dev/null | grep -q "trassir-tgbot" && HAS_TGBOT=1
systemctl list-unit-files 2>/dev/null | grep -q "trassir-tgproxy" && HAS_TGPROXY=1

[ -f "$INSTALL_DIR/app/tg_bot.py" ] && HAS_TGBOT=1
[ -f "$INSTALL_DIR/app/tg_proxy_bot.py" ] && HAS_TGPROXY=1
[ -f "$INSTALL_DIR/config.ini" ] && HAS_TGBOT=1
[ -f "$INSTALL_DIR/config_tgproxy.ini" ] && HAS_TGPROXY=1

if [ $HAS_TGBOT -eq 0 ] && [ $HAS_TGPROXY -eq 0 ]; then
    echo -e "${YELLOW}⚠ Telegram нотифайер не обнаружен.${NC}"
    echo ""
    echo "Проверено:"
    echo "  • Сервис trassir-tgbot"
    echo "  • Сервис trassir-tgproxy"
    echo "  • $INSTALL_DIR/app/tg_bot.py"
    echo "  • $INSTALL_DIR/app/tg_proxy_bot.py"
    exit 0
fi

# ============================================
# ПОКАЗЫВАЕМ ЧТО БУДЕТ УДАЛЕНО
# ============================================
echo -e "${BOLD}Обнаружено:${NC}"
echo ""

if [ $HAS_TGBOT -eq 1 ]; then
    echo -e "  ${CYAN}Обычный Telegram бот (trassir-tgbot):${NC}"
    [ -f "/etc/systemd/system/trassir-tgbot.service" ] && echo "    • /etc/systemd/system/trassir-tgbot.service"
    [ -f "$INSTALL_DIR/app/tg_bot.py" ] && echo "    • $INSTALL_DIR/app/tg_bot.py"
    [ -f "$INSTALL_DIR/config.ini" ] && echo "    • $INSTALL_DIR/config.ini"
    echo ""
fi

if [ $HAS_TGPROXY -eq 1 ]; then
    echo -e "  ${CYAN}Прокси Telegram бот (trassir-tgproxy):${NC}"
    [ -f "/etc/systemd/system/trassir-tgproxy.service" ] && echo "    • /etc/systemd/system/trassir-tgproxy.service"
    [ -f "$INSTALL_DIR/app/tg_proxy_bot.py" ] && echo "    • $INSTALL_DIR/app/tg_proxy_bot.py"
    [ -f "$INSTALL_DIR/config_tgproxy.ini" ] && echo "    • $INSTALL_DIR/config_tgproxy.ini"
    echo ""
fi

echo -e "${GREEN}НЕ будет удалено:${NC}"
echo "  • База данных (trassir.db)"
echo "  • Основной монитор (trassir-monitor)"
echo "  • Настройки в БД (telegram_chats, telegram_settings)"
echo "  • Mail нотифайер (если установлен)"
echo ""

# ============================================
# ВЫБОР ЧТО УДАЛЯТЬ (если установлены оба)
# ============================================
REMOVE_TGBOT=0
REMOVE_TGPROXY=0

if [ $HAS_TGBOT -eq 1 ] && [ $HAS_TGPROXY -eq 1 ]; then
    echo -e "${BOLD}Что удалить?${NC}"
    echo "  1) Только обычный бот (trassir-tgbot)"
    echo "  2) Только прокси бот (trassir-tgproxy)"
    echo "  3) Оба"
    echo ""
    read -p "  Выбор (1/2/3): " CHOICE
    case "$CHOICE" in
        1) REMOVE_TGBOT=1 ;;
        2) REMOVE_TGPROXY=1 ;;
        3) REMOVE_TGBOT=1; REMOVE_TGPROXY=1 ;;
        *) echo -e "${RED}Неверный выбор. Отмена.${NC}"; exit 1 ;;
    esac
elif [ $HAS_TGBOT -eq 1 ]; then
    REMOVE_TGBOT=1
elif [ $HAS_TGPROXY -eq 1 ]; then
    REMOVE_TGPROXY=1
fi

# ============================================
# СОХРАНИТЬ ЛОГИ?
# ============================================
echo ""
read -p "Сохранить логи перед удалением? (y/N): " SAVE_LOGS

if [[ $SAVE_LOGS =~ ^[Yy]$ ]]; then
    BACKUP_DIR="/root/trassir-tgbot-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [ -f "$LOG_DIR/tgbot.log" ]       && cp "$LOG_DIR/tgbot.log" "$BACKUP_DIR/" && echo "  ✓ tgbot.log сохранён"
    [ -f "$LOG_DIR/tgbot-error.log" ] && cp "$LOG_DIR/tgbot-error.log" "$BACKUP_DIR/" && echo "  ✓ tgbot-error.log сохранён"
    [ -f "$LOG_DIR/tgproxy.log" ]     && cp "$LOG_DIR/tgproxy.log" "$BACKUP_DIR/" && echo "  ✓ tgproxy.log сохранён"
    [ -f "$LOG_DIR/tgproxy-error.log" ] && cp "$LOG_DIR/tgproxy-error.log" "$BACKUP_DIR/" && echo "  ✓ tgproxy-error.log сохранён"
    [ -f "$INSTALL_DIR/config.ini" ]       && cp "$INSTALL_DIR/config.ini" "$BACKUP_DIR/" && echo "  ✓ config.ini сохранён"
    [ -f "$INSTALL_DIR/config_tgproxy.ini" ] && cp "$INSTALL_DIR/config_tgproxy.ini" "$BACKUP_DIR/" && echo "  ✓ config_tgproxy.ini сохранён"
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
# УДАЛЯЕМ ОБЫЧНЫЙ БОТ
# ============================================
if [ $REMOVE_TGBOT -eq 1 ]; then
    echo -e "${YELLOW}Удаление trassir-tgbot...${NC}"

    if systemctl is-active --quiet trassir-tgbot 2>/dev/null; then
        systemctl stop trassir-tgbot
        echo "  ✓ Сервис остановлен"
    fi
    if systemctl is-enabled --quiet trassir-tgbot 2>/dev/null; then
        systemctl disable trassir-tgbot
        echo "  ✓ Автозапуск отключён"
    fi

    rm -f /etc/systemd/system/trassir-tgbot.service
    rm -f "$INSTALL_DIR/app/tg_bot.py"
    rm -f "$INSTALL_DIR/config.ini"
    rm -f "$LOG_DIR/tgbot.log"
    rm -f "$LOG_DIR/tgbot-error.log"

    echo -e "  ${GREEN}✓ trassir-tgbot удалён${NC}"
fi

# ============================================
# УДАЛЯЕМ ПРОКСИ БОТ
# ============================================
if [ $REMOVE_TGPROXY -eq 1 ]; then
    echo -e "${YELLOW}Удаление trassir-tgproxy...${NC}"

    if systemctl is-active --quiet trassir-tgproxy 2>/dev/null; then
        systemctl stop trassir-tgproxy
        echo "  ✓ Сервис остановлен"
    fi
    if systemctl is-enabled --quiet trassir-tgproxy 2>/dev/null; then
        systemctl disable trassir-tgproxy
        echo "  ✓ Автозапуск отключён"
    fi

    rm -f /etc/systemd/system/trassir-tgproxy.service
    rm -f "$INSTALL_DIR/app/tg_proxy_bot.py"
    rm -f "$INSTALL_DIR/config_tgproxy.ini"
    rm -f "$LOG_DIR/tgproxy.log"
    rm -f "$LOG_DIR/tgproxy-error.log"

    echo -e "  ${GREEN}✓ trassir-tgproxy удалён${NC}"
fi

# ============================================
# УДАЛЯЕМ ДАННЫЕ ИЗ БД (опционально)
# ============================================
DB_PATH="$INSTALL_DIR/data/trassir.db"
if [ -f "$DB_PATH" ]; then
    echo ""
    read -p "Удалить историю отправок (telegram_logs) из БД? (y/N): " CLEAN_DB
    if [[ $CLEAN_DB =~ ^[Yy]$ ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM telegram_logs;" 2>/dev/null && \
            echo -e "  ${GREEN}✓ telegram_logs очищена${NC}" || \
            echo -e "  ${YELLOW}⚠ Не удалось очистить telegram_logs${NC}"

        read -p "Удалить также получателей (telegram_chats) и настройки (telegram_settings)? (y/N): " CLEAN_SETTINGS
        if [[ $CLEAN_SETTINGS =~ ^[Yy]$ ]]; then
            sqlite3 "$DB_PATH" "DELETE FROM telegram_chats;" 2>/dev/null && \
                echo -e "  ${GREEN}✓ telegram_chats очищена${NC}"
            sqlite3 "$DB_PATH" "DELETE FROM telegram_settings;" 2>/dev/null && \
                echo -e "  ${GREEN}✓ telegram_settings очищена${NC}"
        fi
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
echo -e "${GREEN}║   Telegram нотифайер удалён!                 ║${NC}"
echo -e "${GREEN}║   Основной монитор продолжает работать.      ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверяем статус основного монитора
if systemctl is-active --quiet trassir-monitor 2>/dev/null; then
    echo -e "  ${GREEN}✓ trassir-monitor работает${NC}"
else
    echo -e "  ${YELLOW}⚠ trassir-monitor не запущен${NC}"
    echo -e "     Запустить: ${CYAN}systemctl start trassir-monitor${NC}"
fi
echo ""
