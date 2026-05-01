#!/bin/bash
# ============================================
# TRASSIR Monitor — Удаление Mail Notifier
# ============================================
# Удаляет:
#   - Сервис trassir-mailbot
#   - Файл mail_bot.py
#   - Таблицы БД: mail_recipients, mail_settings, mail_logs
#   - API маршруты из app.py (блок MAIL NOTIFIER API)
#   - Карточку Email из settings.html
#   - Логи mailbot.log / mailbot-error.log
# Сохраняет:
#   - Основной сервис trassir-monitor
#   - Базу данных (таблицы servers, health, alerts и т.д.)
#   - Все остальные файлы проекта
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
SERVICE_MAIL="trassir-mailbot"
SERVICE_MAIN="trassir-monitor"
LOG_DIR="$INSTALL_DIR/logs"
MAILBOT_PY="$INSTALL_DIR/app/mail_bot.py"
APP_PY="$INSTALL_DIR/app/app.py"
SETTINGS_HTML="$INSTALL_DIR/templates/settings.html"
VENV_PYTHON="$INSTALL_DIR/venv/bin/python3"
BACKUP_DIR="$INSTALL_DIR/backups/mail-uninstall-$(date +%Y%m%d_%H%M%S)"

clear

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}║   TRASSIR Monitor — Удаление Mail Notifier   ║${NC}"
echo -e "${RED}║   Сервис, файлы, таблицы БД, API, UI        ║${NC}"
echo -e "${RED}║                                              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# ПРОВЕРКИ
# ============================================

echo -e "${YELLOW}Проверка системы...${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash uninstall-mail-notifier.sh${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Права root"

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}❌ TRASSIR Monitor не найден в $INSTALL_DIR${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} TRASSIR Monitor найден"

# Проверяем что есть что удалять
HAS_SERVICE=0
HAS_BOT_PY=0
HAS_DB_TABLES=0

systemctl list-unit-files "$SERVICE_MAIL.service" 2>/dev/null | grep -q "$SERVICE_MAIL" && HAS_SERVICE=1
[ -f "$MAILBOT_PY" ] && HAS_BOT_PY=1

if [ -f "$VENV_PYTHON" ] && [ -f "$INSTALL_DIR/data/trassir.db" ]; then
    TABLE_CHECK=$($VENV_PYTHON -c "
import sqlite3
conn = sqlite3.connect('$INSTALL_DIR/data/trassir.db')
tables = [r[0] for r in conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()]
conn.close()
print('1' if 'mail_recipients' in tables else '0')
" 2>/dev/null || echo "0")
    [ "$TABLE_CHECK" = "1" ] && HAS_DB_TABLES=1
fi

echo ""
echo -e "${BOLD}Найдено для удаления:${NC}"
[ $HAS_SERVICE -eq 1 ] && echo -e "  ${RED}•${NC} Сервис: $SERVICE_MAIL" || echo -e "  ${YELLOW}—${NC} Сервис: не найден"
[ $HAS_BOT_PY -eq 1 ] && echo -e "  ${RED}•${NC} Файл: $MAILBOT_PY" || echo -e "  ${YELLOW}—${NC} mail_bot.py: не найден"
[ $HAS_DB_TABLES -eq 1 ] && echo -e "  ${RED}•${NC} Таблицы БД: mail_recipients, mail_settings, mail_logs" || echo -e "  ${YELLOW}—${NC} Таблицы БД: не найдены"
echo -e "  ${RED}•${NC} API блок из app.py (MAIL NOTIFIER API)"
echo -e "  ${RED}•${NC} Карточка Email из settings.html"
echo -e "  ${RED}•${NC} Логи: mailbot.log, mailbot-error.log"
echo ""
echo -e "${YELLOW}⚠  Внимание:${NC}"
echo -e "   SMTP-пароль хранится в БД — будет удалён вместе с таблицей mail_settings"
echo ""
echo -e "${YELLOW}Сохраняется:${NC}"
echo -e "  ${GREEN}✓${NC} Основной сервис trassir-monitor"
echo -e "  ${GREEN}✓${NC} База данных (серверы, алерты, история)"
echo -e "  ${GREEN}✓${NC} Все остальные файлы проекта"
echo ""

read -p "Подтвердите удаление (введите YES для продолжения): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo ""
    echo -e "${YELLOW}Отменено.${NC}"
    exit 0
fi
echo ""

# ============================================
# ШАГ 1: БЭКАП ПЕРЕД УДАЛЕНИЕМ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [1/6] СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ             ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

mkdir -p "$BACKUP_DIR"

[ -f "$APP_PY" ]        && cp "$APP_PY"        "$BACKUP_DIR/app.py.bak"        && echo -e "  ${GREEN}✓${NC} app.py сохранён"
[ -f "$SETTINGS_HTML" ] && cp "$SETTINGS_HTML" "$BACKUP_DIR/settings.html.bak" && echo -e "  ${GREEN}✓${NC} settings.html сохранён"
[ -f "$MAILBOT_PY" ]    && cp "$MAILBOT_PY"    "$BACKUP_DIR/mail_bot.py.bak"   && echo -e "  ${GREEN}✓${NC} mail_bot.py сохранён"

# Бэкап SMTP настроек из БД в читаемый вид
if [ -f "$VENV_PYTHON" ] && [ -f "$INSTALL_DIR/data/trassir.db" ]; then
    $VENV_PYTHON << PYEOF 2>/dev/null || true
import sqlite3, json
DB_PATH = '$INSTALL_DIR/data/trassir.db'
try:
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT key, value FROM mail_settings").fetchall()
    conn.close()
    data = dict(rows)
    # Маскируем пароль в бэкапе
    if 'smtp_pass' in data:
        data['smtp_pass'] = '*** СКРЫТ ***'
    with open('$BACKUP_DIR/mail_settings.json', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("  ✓ Настройки SMTP сохранены в бэкап (без пароля)")
except:
    pass
PYEOF
fi

echo "  Бэкап: $BACKUP_DIR"
echo ""
echo -e "${GREEN}✅ Бэкап создан${NC}"
echo ""

# ============================================
# ШАГ 2: ОСТАНОВКА И УДАЛЕНИЕ СЕРВИСА
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [2/6] ОСТАНОВКА И УДАЛЕНИЕ СЕРВИСА         ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if systemctl is-active --quiet "$SERVICE_MAIL" 2>/dev/null; then
    echo "  • Остановка $SERVICE_MAIL..."
    systemctl stop "$SERVICE_MAIL"
    echo -e "  ${GREEN}✓${NC} Сервис остановлен"
else
    echo -e "  ${YELLOW}—${NC} Сервис уже не запущен"
fi

if systemctl is-enabled --quiet "$SERVICE_MAIL" 2>/dev/null; then
    echo "  • Отключение автозапуска..."
    systemctl disable "$SERVICE_MAIL" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Автозапуск отключён"
fi

UNIT_FILE="/etc/systemd/system/$SERVICE_MAIL.service"
if [ -f "$UNIT_FILE" ]; then
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    echo -e "  ${GREEN}✓${NC} Unit-файл удалён: $UNIT_FILE"
else
    echo -e "  ${YELLOW}—${NC} Unit-файл не найден"
fi

echo ""
echo -e "${GREEN}✅ Сервис удалён${NC}"
echo ""

# ============================================
# ШАГ 3: УДАЛЕНИЕ ФАЙЛОВ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [3/6] УДАЛЕНИЕ ФАЙЛОВ                      ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if [ -f "$MAILBOT_PY" ]; then
    rm -f "$MAILBOT_PY"
    echo -e "  ${GREEN}✓${NC} Удалён: $MAILBOT_PY"
else
    echo -e "  ${YELLOW}—${NC} mail_bot.py не найден"
fi

for LOG_FILE in "$LOG_DIR/mailbot.log" "$LOG_DIR/mailbot-error.log"; do
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        echo -e "  ${GREEN}✓${NC} Удалён: $LOG_FILE"
    fi
done

echo ""
echo -e "${GREEN}✅ Файлы удалены${NC}"
echo ""

# ============================================
# ШАГ 4: УДАЛЕНИЕ ТАБЛИЦ ИЗ БД
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [4/6] ОЧИСТКА БАЗЫ ДАННЫХ                  ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if [ -f "$VENV_PYTHON" ] && [ -f "$INSTALL_DIR/data/trassir.db" ]; then
    source "$INSTALL_DIR/venv/bin/activate"
    $VENV_PYTHON << 'PYEOF'
import sqlite3

DB_PATH = '/opt/trassir-monitor/data/trassir.db'
conn = sqlite3.connect(DB_PATH, timeout=10)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA busy_timeout=5000")

tables = ['mail_recipients', 'mail_settings', 'mail_logs']
for table in tables:
    exists = conn.execute(
        f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'"
    ).fetchone()
    if exists:
        conn.execute(f"DROP TABLE IF EXISTS {table}")
        print(f"  ✓ Таблица удалена: {table}")
    else:
        print(f"  — Таблица не найдена: {table}")

conn.execute("VACUUM")
conn.commit()
conn.close()
print("  ✓ База данных очищена")
PYEOF
    deactivate
else
    echo -e "  ${YELLOW}—${NC} Python или БД не найдены, пропускаем"
fi

echo ""
echo -e "${GREEN}✅ База данных очищена${NC}"
echo ""

# ============================================
# ШАГ 5: УДАЛЕНИЕ API ИЗ APP.PY
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [5/6] ОЧИСТКА APP.PY                       ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if [ -f "$APP_PY" ] && grep -q 'MAIL NOTIFIER API' "$APP_PY" 2>/dev/null; then
    source "$INSTALL_DIR/venv/bin/activate"
    $VENV_PYTHON << 'PYEOF'
import re

path = "/opt/trassir-monitor/app/app.py"
with open(path, 'r') as f:
    content = f.read()

pattern = r'\n+# =+\n# MAIL NOTIFIER API.*?(?=\n\n# =====|\nif __name__\b|\Z)'
new_content = re.sub(pattern, '', content, flags=re.DOTALL)

if new_content != content:
    with open(path, 'w') as f:
        f.write(new_content)
    print("  ✓ Блок MAIL NOTIFIER API удалён из app.py")
else:
    print("  — Блок не найден, app.py не изменён")

import ast
try:
    ast.parse(open(path).read())
    print("  ✓ Синтаксис app.py корректен")
except SyntaxError as e:
    print(f"  ❌ Синтаксическая ошибка после правки: {e}")
    print("  Восстанавливаю из бэкапа...")
    import glob, shutil
    backups = sorted(glob.glob('/opt/trassir-monitor/backups/mail-uninstall-*/app.py.bak'))
    if backups:
        shutil.copy(backups[-1], path)
        print("  ✓ Восстановлено")
PYEOF
    deactivate
else
    echo -e "  ${YELLOW}—${NC} Блок MAIL NOTIFIER API не найден в app.py"
fi

echo ""
echo -e "${GREEN}✅ app.py очищен${NC}"
echo ""

# ============================================
# ШАГ 6: УДАЛЕНИЕ КАРТОЧКИ ИЗ SETTINGS.HTML
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [6/6] ОЧИСТКА SETTINGS.HTML                ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if [ -f "$SETTINGS_HTML" ] && grep -qE 'mailLoadSettings|api/mail|mail_recipients|mail_settings' "$SETTINGS_HTML" 2>/dev/null; then
    source "$INSTALL_DIR/venv/bin/activate"
    $VENV_PYTHON << 'PYEOF'
import re

path = "/opt/trassir-monitor/templates/settings.html"
with open(path, 'r') as f:
    content = f.read()

original = content

# Удаляем col-lg-* блок, содержащий маркеры mail-нотификатора.
# Стратегия: находим открывающий <div class="col-lg-..."> перед маркером
# и балансируем теги div до закрывающего </div>, затем убираем весь блок.
MAIL_MARKERS = ['mailLoadSettings', 'api/mail', 'mail_recipients', 'mail_settings',
                'Email уведомления', 'Email-уведомления', 'SMTP']

def find_col_block_to_remove(text, markers):
    """Найти и удалить col-lg-* div-блок, содержащий хотя бы один маркер."""
    # Ищем позицию маркера
    marker_pos = -1
    for m in markers:
        idx = text.find(m)
        if idx != -1:
            if marker_pos == -1 or idx < marker_pos:
                marker_pos = idx
    if marker_pos == -1:
        return text, False

    # Ищем назад открывающий col-блок
    col_pattern = re.compile(r'<div\s+class=["\'][^"\']*col-(?:lg|md|sm|xs)-\d+[^"\']*["\']', re.IGNORECASE)
    col_start = -1
    for m in col_pattern.finditer(text):
        if m.start() < marker_pos:
            col_start = m.start()
        else:
            break
    if col_start == -1:
        return text, False

    # Балансируем div-теги начиная с col_start
    depth = 0
    i = col_start
    open_tag = re.compile(r'<div[\s>]', re.IGNORECASE)
    close_tag = re.compile(r'</div\s*>', re.IGNORECASE)
    while i < len(text):
        o = open_tag.match(text, i)
        c = close_tag.match(text, i)
        if o:
            depth += 1
            i = o.end()
        elif c:
            depth -= 1
            i = c.end()
            if depth == 0:
                break
        else:
            i += 1

    block = text[col_start:i]
    # Убираем предшествующие пробелы/переносы, чтобы не оставлять пустых строк
    before = text[:col_start].rstrip(' \t')
    after = text[i:].lstrip('\n')
    return before + '\n' + after, True

content, removed = find_col_block_to_remove(content, MAIL_MARKERS)

if removed:
    print("  ✓ Карточка Email удалена из settings.html")
else:
    print("  — Карточка Email не найдена по маркерам (возможно уже удалена)")

# Удаляем JS-блок mail-функций и вызов mailRefresh() / mailInit() и т.п.
# Ищем <script>...</script> блоки, упоминающие mail* функции
def remove_mail_scripts(text):
    script_re = re.compile(r'(<script[^>]*>)(.*?)(</script\s*>)', re.DOTALL | re.IGNORECASE)
    def replacer(m):
        body = m.group(2)
        if re.search(r'\bmail[A-Z]\w+\s*[=(]|api/mail|mailRefresh|mailInit|mailLoad', body):
            return ''
        return m.group(0)
    return script_re.sub(replacer, text)

content_after = remove_mail_scripts(content)
if content_after != content:
    content = content_after
    print("  ✓ JS-блок mail-функций удалён")

if content != original:
    with open(path, 'w') as f:
        f.write(content)
    print("  ✓ settings.html сохранён")
else:
    print("  — settings.html не изменён")
PYEOF
    deactivate
else
    echo -e "  ${YELLOW}—${NC} Блок Email не найден в settings.html"
fi

echo ""
echo -e "${GREEN}✅ settings.html очищен${NC}"
echo ""

# ============================================
# ПЕРЕЗАПУСК ОСНОВНОГО СЕРВИСА
# ============================================

if systemctl is-active --quiet "$SERVICE_MAIN" 2>/dev/null; then
    echo "  • Перезапуск $SERVICE_MAIN для применения изменений..."
    systemctl restart "$SERVICE_MAIN"
    sleep 2
    STATUS=$(systemctl is-active "$SERVICE_MAIN" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} Статус: $STATUS"
    echo ""
fi

# ============================================
# ИТОГ
# ============================================

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Mail Notifier — УДАЛЁН ✓                   ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Что удалено:${NC}"
echo -e "   ${RED}✗${NC} Сервис trassir-mailbot"
echo -e "   ${RED}✗${NC} $MAILBOT_PY"
echo -e "   ${RED}✗${NC} Таблицы mail_recipients / mail_settings / mail_logs"
echo -e "   ${RED}✗${NC} SMTP настройки (включая пароль)"
echo -e "   ${RED}✗${NC} API /api/mail/* из app.py"
echo -e "   ${RED}✗${NC} Карточка Email из /settings"
echo -e "   ${RED}✗${NC} Лог-файлы mailbot.log"
echo ""
echo -e "${BOLD}Что сохранено:${NC}"
echo -e "   ${GREEN}✓${NC} Сервис trassir-monitor (работает)"
echo -e "   ${GREEN}✓${NC} База данных (серверы, алерты, история)"
echo -e "   ${GREEN}✓${NC} Бэкап файлов: ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "  Для повторной установки:"
echo -e "  ${YELLOW}sudo bash install-mail-notifier.sh${NC}"
echo ""
