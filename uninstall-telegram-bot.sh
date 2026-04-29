#!/bin/bash
# ============================================
# TRASSIR Monitor — Удаление Telegram Bot
# Удаляет ТОЛЬКО Telegram-бота и его файлы
# TRASSIR Monitor остаётся нетронутым
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
SERVICE_BOT="trassir-tgbot"
SERVICE_MAIN="trassir-monitor"
CONFIG_FILE="$INSTALL_DIR/config.ini"
BACKUP_DIR="$INSTALL_DIR/backups/telegram-$(date +%Y%m%d_%H%M%S)"

clear

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}║   УДАЛЕНИЕ Telegram Bot                      ║${NC}"
echo -e "${RED}║   TRASSIR Monitor останется нетронутым       ║${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root: sudo bash uninstall-telegram-bot.sh${NC}"
    exit 1
fi

# Проверка что бот установлен
if [ ! -f "$INSTALL_DIR/app/tg_bot.py" ] && [ ! -f "/etc/systemd/system/$SERVICE_BOT.service" ]; then
    echo -e "${YELLOW}⚠ Telegram Bot не обнаружен в системе.${NC}"
    echo "  Нечего удалять."
    exit 0
fi

echo -e "${YELLOW}Будет удалено:${NC}"
echo "  • Сервис: $SERVICE_BOT"
echo "  • Файл бота: $INSTALL_DIR/app/tg_bot.py"
echo "  • Интеграция API из app.py"
echo "  • Блок Telegram из settings.html"
echo "  • Конфиг: $CONFIG_FILE"
echo ""
echo -e "${GREEN}Будет сохранено:${NC}"
echo "  • TRASSIR Monitor (полностью)"
echo "  • База данных trassir.db"
echo "  • Таблицы telegram_chats, telegram_settings, telegram_logs"
echo "  • Серверы и алерты"
echo ""

read -p "Для подтверждения введите DELETE заглавными буквами: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo ""
    echo -e "${GREEN}✅ Отмена удаления${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Выполняю удаление...${NC}"
echo ""

# Создаём бэкап перед удалением
echo "  • Создание бэкапа..."
mkdir -p "$BACKUP_DIR"
cp "$INSTALL_DIR/app/app.py" "$BACKUP_DIR/app.py.bak" 2>/dev/null && echo "    ✓ app.py сохранён"
cp "$INSTALL_DIR/templates/settings.html" "$BACKUP_DIR/settings.html.bak" 2>/dev/null && echo "    ✓ settings.html сохранён"
cp "$CONFIG_FILE" "$BACKUP_DIR/config.ini.bak" 2>/dev/null && echo "    ✓ config.ini сохранён"
echo "    Бэкап: $BACKUP_DIR"
echo ""

# Остановка и удаление сервиса
echo "  • Остановка сервиса..."
systemctl stop "$SERVICE_BOT" 2>/dev/null && echo "    ✓ Сервис остановлен" || echo "    ⚠ Сервис не запущен"
systemctl disable "$SERVICE_BOT" 2>/dev/null && echo "    ✓ Автозапуск отключён" || echo "    ⚠ Автозапуск не настроен"
rm -f "/etc/systemd/system/$SERVICE_BOT.service"
systemctl daemon-reload
echo "    ✓ Файл сервиса удалён"
echo ""

# Удаление файла бота
echo "  • Удаление файлов бота..."
rm -f "$INSTALL_DIR/app/tg_bot.py"
rm -f "$INSTALL_DIR/app/tg_bot.pyc"
rm -rf "$INSTALL_DIR/app/__pycache__"
echo "    ✓ tg_bot.py удалён"
echo ""

# Удаление конфига
echo "  • Удаление конфигурации..."
rm -f "$CONFIG_FILE"
echo "    ✓ config.ini удалён"
echo ""

# Удаление логов
echo "  • Удаление логов..."
rm -f "$INSTALL_DIR/logs/tgbot.log"
rm -f "$INSTALL_DIR/logs/tgbot-error.log"
echo "    ✓ Логи удалены"
echo ""

# Очистка API из app.py
echo "  • Удаление Telegram API из app.py..."
source "$INSTALL_DIR/venv/bin/activate" 2>/dev/null

python3 << 'PYEOF'
import re

app_path = "/opt/trassir-monitor/app/app.py"

with open(app_path, 'r') as f:
    content = f.read()

# Удаляем блок TELEGRAM BOT API
# Паттерн: от "# =" до 'if __name__'
content = re.sub(
    r'\n# =+\n# TELEGRAM BOT API.*?(?=\nif __name__)',
    '',
    content,
    flags=re.DOTALL
)

# Удаляем import telegram_notifier если есть
content = re.sub(
    r'\n?# Telegram Notifier\nfrom app\.telegram_notifier import notify_server_alerts\n?',
    '\n',
    content
)

# Удаляем вызовы notify_server_alerts если есть
content = re.sub(
    r'\s*# =+\n\s*# ОТПРАВЛЯЕМ TELEGRAM.*?\n\s*except.*?\n',
    '',
    content,
    flags=re.DOTALL
)

with open(app_path, 'w') as f:
    f.write(content)

print("    ✓ API удалён из app.py")
PYEOF

# Проверка синтаксиса
if python3 -c "import ast; ast.parse(open('$INSTALL_DIR/app/app.py').read()); print('    ✓ Синтаксис app.py корректен')" 2>/dev/null; then
    echo "    ✓ Проверка пройдена"
else
    echo "    ⚠ Ошибка синтаксиса! Восстанавливаю из бэкапа..."
    cp "$BACKUP_DIR/app.py.bak" "$INSTALL_DIR/app/app.py"
    echo "    ✓ Восстановлено"
fi

deactivate
echo ""

# Очистка Telegram из settings.html
echo "  • Удаление блока Telegram из settings.html..."

python3 << 'PYEOF'
import re

html_path = "/opt/trassir-monitor/templates/settings.html"

with open(html_path, 'r') as f:
    content = f.read()

# Удаляем всё между <!-- TELEGRAM --> и </script> перед {% endblock %}
# Многократно пока есть вхождения
while True:
    start = content.find('<!-- ============================================ -->\n    <!-- TELEGRAM')
    if start == -1:
        break
    
    # Ищем конец — {% endblock %}
    endblock = content.find('{% endblock %}', start)
    if endblock == -1:
        break
    
    # Ищем последний </script> перед endblock
    script_end = content.rfind('</script>', start, endblock)
    if script_end == -1:
        break
    
    # Ищем закрывающий </div> после скрипта
    div_end = content.find('\n</div>', script_end)
    if div_end == -1 or div_end > endblock:
        div_end = script_end + len('</script>\n')
    else:
        div_end += len('\n</div>\n')
    
    content = content[:start] + content[div_end:]
    print("    ✓ Удалён блок Telegram")

with open(html_path, 'w') as f:
    f.write(content)

remaining = content.count('tgStatusBadge') + content.count('tgBadge')
print(f"    Осталось маркеров Telegram: {remaining}")
PYEOF

echo ""

# Перезапуск основного сервиса
echo "  • Перезапуск TRASSIR Monitor..."
systemctl restart "$SERVICE_MAIN" 2>/dev/null && echo "    ✓ Сервис перезапущен" || echo "    ⚠ Не удалось перезапустить"
echo ""

# Финальный вывод
IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Telegram Bot — УДАЛЁН                      ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}✅ Удалено:${NC}"
echo "  • Сервис Telegram бота"
echo "  • Файл tg_bot.py"
echo "  • config.ini"
echo "  • API из app.py"
echo "  • Блок из settings.html"
echo "  • Логи бота"
echo ""
echo -e "${BOLD}💾 Сохранено:${NC}"
echo "  • TRASSIR Monitor"
echo "  • База данных (telegram_chats, telegram_settings, telegram_logs)"
echo "  • Серверы, алерты, история"
echo ""
echo -e "${BOLD}📁 Бэкап перед удалением:${NC}"
echo "  $BACKUP_DIR"
echo ""
echo -e "${BOLD}🔧 Если нужно восстановить:${NC}"
echo "  1. Установите заново: sudo bash install-telegram-bot-final.sh"
echo "  2. Или восстановите из бэкапа:"
echo "     cp $BACKUP_DIR/app.py.bak $INSTALL_DIR/app/app.py"
echo "     cp $BACKUP_DIR/settings.html.bak $INSTALL_DIR/templates/settings.html"
echo ""
