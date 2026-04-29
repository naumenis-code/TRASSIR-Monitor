#!/bin/bash
# ============================================
# TRASSIR Monitor — Telegram Bot Installer v6.0 FINAL
# ============================================
# Все надписи на русском языке
# Формат уведомлений как в примере
# Чистая замена шаблона settings.html
# Бот читает из БД, не спамит
# Редактирование получателей через Web
# ============================================
set -e

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
LOG_DIR="$INSTALL_DIR/logs"
TGBOT_PY="$INSTALL_DIR/app/tg_bot.py"
APP_PY="$INSTALL_DIR/app/app.py"
SETTINGS_HTML="$INSTALL_DIR/templates/settings.html"
VENV_PYTHON="$INSTALL_DIR/venv/bin/python3"

clear

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                              ║${NC}"
echo -e "${CYAN}║   TRASSIR Monitor — Telegram Bot v6.0 FINAL  ║${NC}"
echo -e "${CYAN}║   Автономный демон + Web-управление          ║${NC}"
echo -e "${CYAN}║   HTTP-прокси • Много получателей            ║${NC}"
echo -e "${CYAN}║   Debian 11/12/13                            ║${NC}"
echo -e "${CYAN}║   Русский язык                               ║${NC}"
echo -e "${CYAN}║                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# ПРОВЕРКИ ПЕРЕД УСТАНОВКОЙ
# ============================================

echo -e "${YELLOW}Проверка системы...${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash install-telegram-bot-final.sh${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Права root"

if [ ! -f "$APP_PY" ]; then
    echo -e "${RED}❌ TRASSIR Monitor не найден в $INSTALL_DIR${NC}"
    echo -e "   Сначала установите TRASSIR Monitor:"
    echo -e "   ${YELLOW}sudo bash install-trassir-monitor16.sh${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} TRASSIR Monitor найден"

if [ ! -f "$VENV_PYTHON" ]; then
    echo -e "${RED}❌ Виртуальное окружение Python не найдено${NC}"
    echo -e "   Путь: $VENV_PYTHON"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Виртуальное окружение Python"

if systemctl is-active --quiet "$SERVICE_BOT" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}⚠ Telegram Bot уже установлен и запущен.${NC}"
    echo -e "  Будет выполнена переустановка с сохранением базы данных."
    echo -e "  Сервис: ${BOLD}$SERVICE_BOT${NC}"
    echo ""
    read -p "  Продолжить? (Enter — да, Ctrl+C — отмена): " confirm
    echo ""
    echo -e "  • Остановка старого бота..."
    systemctl stop "$SERVICE_BOT" 2>/dev/null || true
    systemctl disable "$SERVICE_BOT" 2>/dev/null || true
    echo "    ✓ Старый бот остановлен"
fi

echo ""

# ============================================
# ЗАПРОС ПАРАМЕТРОВ У ПОЛЬЗОВАТЕЛЯ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  НАСТРОЙКА TELEGRAM БОТА                     ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  Все параметры можно изменить позже:"
echo -e "  • Токен и прокси: ${CYAN}$CONFIG_FILE${NC}"
echo -e "  • Получатели: через веб-интерфейс /settings"
echo ""

echo -e "  ${BOLD}1. Токен Telegram бота${NC}"
echo -e "     Получите у @BotFather в Telegram командой /newbot"
echo -e "     Формат: 123456789:ABCdefGHIjklmNOPqrstUVwxyz"
echo ""
read -p "     Токен: " TG_TOKEN

while [ -z "$TG_TOKEN" ]; do
    echo -e "     ${RED}⚠ Токен обязателен для работы бота!${NC}"
    read -p "     Токен: " TG_TOKEN
done

if echo "$TG_TOKEN" | grep -qE '^[0-9]+:[a-zA-Z0-9_-]+$'; then
    echo -e "     ${GREEN}✓${NC} Формат токена корректен"
else
    echo -e "     ${YELLOW}⚠${NC} Нестандартный формат токена. Продолжаем."
fi
echo ""

echo -e "  ${BOLD}2. Chat ID получателей${NC}"
echo -e "     ID чатов через запятую (можно несколько)"
echo -e "     Как узнать: напишите боту @userinfobot в Telegram"
echo -e "     Пример: 1534965455,212715740,5641611513"
echo ""
read -p "     Chat IDs: " TG_CHATS

while [ -z "$TG_CHATS" ]; do
    echo -e "     ${RED}⚠ Хотя бы один Chat ID обязателен!${NC}"
    read -p "     Chat IDs: " TG_CHATS
done

CHAT_COUNT=$(echo "$TG_CHATS" | tr ',' '\n' | sed 's/ //g' | grep -c '^')
echo -e "     ${GREEN}✓${NC} Указано чатов: $CHAT_COUNT"
echo ""

echo -e "  ${BOLD}3. HTTP-прокси для Telegram${NC}"
echo -e "     Укажите если Telegram заблокирован в вашей сети"
echo -e "     Формат: http://login:password@host:port"
echo -e "     Оставьте пустым для прямого подключения"
echo ""
read -p "     Прокси (Enter — без прокси): " TG_PROXY

if [ -n "$TG_PROXY" ]; then
    MASKED_PROXY=$(echo "$TG_PROXY" | sed -E 's/(:\/\/[^:]+:)([^@]+)(@)/\1***\3/')
    echo -e "     ${GREEN}✓${NC} Прокси настроен: $MASKED_PROXY"
else
    echo -e "     ${GREEN}✓${NC} Прямое подключение к api.telegram.org"
fi
echo ""

echo -e "  ${BOLD}4. Интервал проверки базы данных${NC}"
echo -e "     Как часто (в секундах) бот проверяет новые алерты"
echo -e "     Рекомендуется: 10 секунд (минимум 5)"
echo ""
read -p "     Интервал (Enter для 10): " CHECK_INTERVAL
CHECK_INTERVAL=${CHECK_INTERVAL:-10}

if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [ "$CHECK_INTERVAL" -lt 5 ]; then
    echo -e "     ${YELLOW}⚠${NC} Интервал должен быть не менее 5 секунд"
    echo -e "     Установлено значение по умолчанию: 10 секунд"
    CHECK_INTERVAL=10
fi
echo -e "     ${GREEN}✓${NC} Интервал: $CHECK_INTERVAL сек"
echo ""

echo -e "  ${BOLD}5. URL веб-интерфейса монитора${NC}"
echo -e "     Будет добавлен в сообщения как ссылка для быстрого перехода"
echo -e "     Оставьте пустым если не нужен"
echo ""
DEFAULT_URL="http://$(hostname -I | awk '{print $1}'):8080"
read -p "     URL (Enter для $DEFAULT_URL): " MONITOR_URL
MONITOR_URL=${MONITOR_URL:-$DEFAULT_URL}
echo -e "     ${GREEN}✓${NC} URL: $MONITOR_URL"
echo ""

# ============================================
# ПОДТВЕРЖДЕНИЕ ПАРАМЕТРОВ
# ============================================

echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ПАРАМЕТРЫ УСТАНОВКИ               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  🔑 Токен:      ${BOLD}${TG_TOKEN:0:12}...${TG_TOKEN: -4}${NC}"
echo -e "  👥 Чаты:       ${BOLD}${TG_CHATS}${NC} ($CHAT_COUNT шт.)"
if [ -n "$TG_PROXY" ]; then
    echo -e "  🌐 Прокси:     ${BOLD}$MASKED_PROXY${NC}"
else
    echo -e "  🌐 Прокси:     ${BOLD}не используется${NC}"
fi
echo -e "  ⏱  Интервал:   ${BOLD}${CHECK_INTERVAL} сек${NC}"
echo -e "  🔗 URL:        ${BOLD}${MONITOR_URL}${NC}"
echo -e "  📁 Установка:  ${BOLD}${INSTALL_DIR}${NC}"
echo -e "  💾 Бэкап:      ${BOLD}${BACKUP_DIR}${NC}"
echo ""

read -p "Всё верно? Нажмите Enter для продолжения (Ctrl+C для отмены): " confirm
echo ""

# ============================================
# ШАГ 0: БЭКАП СУЩЕСТВУЮЩИХ ФАЙЛОВ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [0/7] СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ             ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

mkdir -p "$BACKUP_DIR"
echo "  Создание бэкапа в $BACKUP_DIR"
echo ""

if [ -f "$APP_PY" ]; then
    cp "$APP_PY" "$BACKUP_DIR/app.py.bak"
    echo -e "  ${GREEN}✓${NC} app.py сохранён ($(wc -c < "$BACKUP_DIR/app.py.bak") байт)"
else
    echo -e "  ${YELLOW}⚠${NC} app.py не найден (пропускаем)"
fi

if [ -f "$SETTINGS_HTML" ]; then
    cp "$SETTINGS_HTML" "$BACKUP_DIR/settings.html.bak"
    echo -e "  ${GREEN}✓${NC} settings.html сохранён ($(wc -c < "$BACKUP_DIR/settings.html.bak") байт)"
else
    echo -e "  ${YELLOW}⚠${NC} settings.html не найден (пропускаем)"
fi

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_DIR/config.ini.bak"
    echo -e "  ${GREEN}✓${NC} config.ini сохранён"
else
    echo -e "  ${YELLOW}⚠${NC} config.ini не найден (создадим новый)"
fi

echo ""
echo -e "${GREEN}✅ Бэкап создан успешно${NC}"
echo ""

# ============================================
# ШАГ 1: КОНФИГУРАЦИЯ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [1/7] СОХРАНЕНИЕ КОНФИГУРАЦИИ              ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

cat > "$CONFIG_FILE" << CONFEOF
[telegram]
token = $TG_TOKEN
proxy = $TG_PROXY
monitor_url = $MONITOR_URL
CONFEOF

chmod 600 "$CONFIG_FILE"
chown www-data:www-data "$CONFIG_FILE" 2>/dev/null || true

echo "  • Файл: $CONFIG_FILE"
echo "  • Права: 600 (только root)"
echo "  • Владелец: www-data"
echo "  • Размер: $(wc -c < "$CONFIG_FILE") байт"
echo ""
echo "  Содержимое конфигурации:"
echo "  ----------------------------------------"
echo "  [telegram]"
echo "  token = ${TG_TOKEN:0:12}...${TG_TOKEN: -4}"
echo "  proxy = ${TG_PROXY:-не указан}"
echo "  monitor_url = $MONITOR_URL"
echo "  ----------------------------------------"

echo ""
echo -e "${GREEN}✅ Конфигурация сохранена${NC}"
echo ""

# ============================================
# ШАГ 2: ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [2/7] ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ            ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

source "$INSTALL_DIR/venv/bin/activate"

export TG_CHATS_ENV="$TG_CHATS"

$VENV_PYTHON << 'PYEOF'
import sqlite3
import os

DB_PATH = '/opt/trassir-monitor/data/trassir.db'

print("  • Подключение к базе данных...")
conn = sqlite3.connect(DB_PATH)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA busy_timeout=5000")
conn.row_factory = sqlite3.Row
print("    ✓ Подключено (WAL режим)")

print("")
print("  • Создание таблиц Telegram:")

conn.execute("""
    CREATE TABLE IF NOT EXISTS telegram_chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT NOT NULL UNIQUE,
        name TEXT DEFAULT '',
        enabled BOOLEAN DEFAULT 1,
        warning BOOLEAN DEFAULT 1,
        critical BOOLEAN DEFAULT 1,
        info BOOLEAN DEFAULT 0,
        added_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
""")
print("    ✓ telegram_chats (получатели)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS telegram_settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )
""")
print("    ✓ telegram_settings (настройки)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS telegram_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts DATETIME,
        alert_key TEXT,
        chat_id TEXT,
        message TEXT
    )
""")
print("    ✓ telegram_logs (история отправок)")

conn.execute("CREATE INDEX IF NOT EXISTS idx_tg_logs_key ON telegram_logs(alert_key, ts)")
conn.execute("CREATE INDEX IF NOT EXISTS idx_tg_chats_enabled ON telegram_chats(enabled)")
print("    ✓ Индексы созданы")

conn.execute("INSERT OR IGNORE INTO telegram_settings (key, value) VALUES ('enabled', '1')")
conn.execute("INSERT OR IGNORE INTO telegram_settings (key, value) VALUES ('notify_interval', '0')")
print("    ✓ Настройки по умолчанию")

print("")
print("  • Добавление получателей:")

chat_list = os.environ.get('TG_CHATS_ENV', '').split(',')
added_count = 0
for chat_id in chat_list:
    chat_id = chat_id.strip()
    if chat_id:
        try:
            conn.execute(
                "INSERT OR IGNORE INTO telegram_chats (chat_id) VALUES (?)",
                (chat_id,)
            )
            print(f"    ✓ Chat ID {chat_id} добавлен")
            added_count += 1
        except Exception as e:
            print(f"    ⚠ Ошибка добавления {chat_id}: {e}")

total_chats = conn.execute("SELECT COUNT(*) FROM telegram_chats").fetchone()[0]
enabled_chats = conn.execute("SELECT COUNT(*) FROM telegram_chats WHERE enabled=1").fetchone()[0]
print(f"    Всего получателей: {total_chats} (активных: {enabled_chats})")

conn.commit()
conn.close()
print("")
print("  ✅ База данных готова к работе")
PYEOF

deactivate

echo ""
echo -e "${GREEN}✅ База данных инициализирована${NC}"
echo ""

# ============================================
# ШАГ 3: СОЗДАНИЕ TELEGRAM БОТА (tg_bot.py)
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [3/7] СОЗДАНИЕ TELEGRAM БОТА               ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Генерация tg_bot.py..."

cat > "$TGBOT_PY" << 'TGBOTEOF'
#!/usr/bin/env python3
"""
TRASSIR Monitor — Telegram Bot Daemon v6.0
Автономный мониторинг базы данных и отправка уведомлений в Telegram

Принцип работы:
1. Проверяет таблицу alerts каждые N секунд
2. Находит новые алерты (отсутствующие в telegram_logs)
3. Форматирует красивое HTML-сообщение на русском языке
4. Отправляет всем подписанным получателям
5. Помечает алерт как отправленный

Особенности:
- Не зависит от основного цикла опроса серверов
- Поддержка HTTP/HTTPS прокси
- Защита от повторной отправки
- Детальное логирование
- Автоматическая очистка старых логов
"""

import os
import sys
import time
import sqlite3
import requests
import configparser
from datetime import datetime

# ============================================
# КОНФИГУРАЦИЯ
# ============================================

BASE_DIR = "/opt/trassir-monitor"
CONFIG_FILE = os.path.join(BASE_DIR, "config.ini")
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
CHECK_INTERVAL = 10

# ============================================
# РАБОТА С КОНФИГУРАЦИОННЫМ ФАЙЛОМ
# ============================================

def get_config():
    """
    Читает конфигурацию из config.ini
    
    Возвращает:
        dict с ключами token, proxy, monitor_url или None
    """
    try:
        cfg = configparser.ConfigParser()
        cfg.read(CONFIG_FILE)
        
        if 'telegram' not in cfg:
            return None
        
        return {
            'token': cfg['telegram'].get('token', ''),
            'proxy': cfg['telegram'].get('proxy', ''),
            'monitor_url': cfg['telegram'].get('monitor_url', '')
        }
    except Exception as e:
        print(f"[{datetime.now()}] Ошибка чтения конфигурации: {e}")
        return None


def get_proxies():
    """
    Формирует словарь прокси для requests
    
    Возвращает:
        dict с http и https прокси или пустой dict
    """
    cfg = get_config()
    if not cfg or not cfg['proxy']:
        return {}
    
    proxy_url = cfg['proxy']
    return {
        'http': proxy_url,
        'https': proxy_url
    }


# ============================================
# ОТПРАВКА СООБЩЕНИЙ В TELEGRAM
# ============================================

def send_telegram_message(chat_id, text):
    """
    Отправляет сообщение в Telegram через Bot API
    
    Аргументы:
        chat_id: ID чата получателя
        text: текст сообщения в формате HTML
    
    Возвращает:
        bool: True если отправка успешна
    """
    cfg = get_config()
    
    if not cfg or not cfg['token']:
        print(f"[{datetime.now()}] ❌ Ошибка: токен не настроен")
        return False
    
    if not chat_id:
        print(f"[{datetime.now()}] ❌ Ошибка: не указан chat_id")
        return False
    
    try:
        url = f"https://api.telegram.org/bot{cfg['token']}/sendMessage"
        
        payload = {
            'chat_id': chat_id,
            'text': text,
            'parse_mode': 'HTML',
            'disable_web_page_preview': True
        }
        
        proxies = get_proxies()
        
        response = requests.post(
            url,
            json=payload,
            proxies=proxies,
            timeout=15
        )
        
        if response.status_code == 200:
            result = response.json()
            if result.get('ok'):
                return True
            else:
                error_desc = result.get('description', 'Неизвестная ошибка')
                print(f"[{datetime.now()}] ❌ Ошибка Telegram API: {error_desc}")
                return False
        else:
            print(f"[{datetime.now()}] ❌ Ошибка HTTP: {response.status_code}")
            return False
    
    except requests.exceptions.Timeout:
        print(f"[{datetime.now()}] ❌ Таймаут подключения к Telegram")
        return False
    except requests.exceptions.ProxyError as e:
        print(f"[{datetime.now()}] ❌ Ошибка прокси: {e}")
        return False
    except requests.exceptions.ConnectionError:
        print(f"[{datetime.now()}] ❌ Ошибка соединения. Проверьте интернет/прокси")
        return False
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Неизвестная ошибка: {e}")
        return False


# ============================================
# ФОРМАТИРОВАНИЕ СООБЩЕНИЙ
# ============================================

def format_uptime(seconds):
    """
    Форматирует uptime из секунд в читаемый вид
    
    Аргументы:
        seconds: количество секунд
    
    Возвращает:
        строка вида "5д 12ч 30м"
    """
    if not seconds:
        return "Н/Д"
    
    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return str(seconds)
    
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    
    if days > 0:
        return f"{days}д {hours}ч {minutes}м"
    elif hours > 0:
        return f"{hours}ч {minutes}м"
    else:
        return f"{minutes}м"


def format_alert_message(alert_data):
    """
    Форматирует алерт в красивое HTML-сообщение для Telegram
    
    Аргументы:
        alert_data: словарь с данными алерта и сервера
    
    Возвращает:
        строка с HTML-форматированием на русском языке
    """
    level = alert_data.get('level', 'warning')
    message = alert_data.get('msg', 'Неизвестная проблема')
    server_name = alert_data.get('server_name', 'Неизвестный сервер')
    server_ip = alert_data.get('server_ip', 'Неизвестный IP')
    server_id = alert_data.get('server_id', '')
    timestamp = alert_data.get('ts', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    health = alert_data.get('health', {})
    
    msg_lower = message.lower()
    
    if level == 'critical':
        emoji = '🔴'
        header = '🚨 КРИТИЧЕСКИЙ АЛЕРТ'
    elif 'камер' in msg_lower or 'camera' in msg_lower:
        emoji = '📷'
        header = 'ОТВАЛ КАМЕР'
    elif 'cpu' in msg_lower or 'процессор' in msg_lower:
        emoji = '🔥'
        header = 'ВЫСОКАЯ НАГРУЗКА CPU'
    elif 'архив' in msg_lower or 'archive' in msg_lower:
        emoji = '💾'
        header = 'ПРОБЛЕМА С АРХИВОМ'
    elif 'диск' in msg_lower or 'disk' in msg_lower:
        emoji = '💿'
        header = 'ОШИБКА ДИСКОВ'
    else:
        emoji = '🟡'
        header = 'ПРЕДУПРЕЖДЕНИЕ'
    
    cfg = get_config()
    monitor_url = cfg.get('monitor_url', '') if cfg else ''
    
    cpu_val = health.get('cpu', '?')
    cpu_str = f"{cpu_val:.1f}%" if isinstance(cpu_val, (int, float)) else f"{cpu_val}%"
    
    arch_val = health.get('arch', '?')
    arch_str = f"{arch_val:.1f} дн" if isinstance(arch_val, (int, float)) else f"{arch_val} дн"
    
    text = f"""{emoji} <b>{header}</b>

🖥 <b>Сервер:</b> {server_name}
📍 <b>IP адрес:</b> {server_ip}

⚠ <b>Проблема:</b> {message}

📊 <b>Текущее состояние сервера:</b>
  • Загрузка процессора: <b>{cpu_str}</b>
  • Камер онлайн: <b>{health.get('ch_online', '?')} из {health.get('ch_total', '?')}</b>
  • Глубина архива: <b>{arch_str}</b>
  • Время работы (uptime): <b>{format_uptime(health.get('uptime', 0))}</b>
  • Время отклика: <b>{health.get('rt', '?')} мс</b>

🕐 {timestamp} МСК"""
    
    if monitor_url and server_id:
        text += f"\n\n🔗 <a href='{monitor_url}/server/{server_id}'>Открыть в TRASSIR Monitor</a>"
    
    return text


def format_test_message(monitor_url=""):
    """
    Форматирует тестовое сообщение
    
    Аргументы:
        monitor_url: URL веб-интерфейса
    
    Возвращает:
        строка с HTML-форматированием
    """
    ts = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
    
    text = f"""✅ <b>TRASSIR Monitor — Бот установлен!</b>

🖥 <b>Система мониторинга активна</b>
📍 <b>Веб-интерфейс:</b> {monitor_url or 'не указан'}

✅ Все системы работают корректно
📡 Telegram-уведомления успешно настроены

⏰ {ts} МСК"""
    
    return text


# ============================================
# РАБОТА С БАЗОЙ ДАННЫХ
# ============================================

def get_database_connection():
    """
    Создаёт и возвращает подключение к БД с правильными настройками
    """
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.row_factory = sqlite3.Row
    return conn


def get_new_alerts():
    """
    Получает список НОВЫХ алертов (ещё не отправленных в Telegram)
    
    Возвращает:
        list[dict]: список алертов с полной информацией
    """
    conn = get_database_connection()
    
    try:
        query = """
            SELECT 
                a.id,
                a.server_id,
                a.level,
                a.msg,
                a.ts,
                a.ack,
                s.name as server_name,
                s.ip as server_ip
            FROM alerts a
            JOIN servers s ON a.server_id = s.id
            WHERE a.ack = 0
            AND a.id NOT IN (
                SELECT DISTINCT CAST(alert_key AS INTEGER) 
                FROM telegram_logs 
                WHERE alert_key GLOB '[0-9]*'
            )
            ORDER BY a.ts ASC
        """
        
        alerts = conn.execute(query).fetchall()
        
        result = []
        for alert in alerts:
            alert_dict = dict(alert)
            
            health_row = conn.execute(
                """SELECT cpu, disks, ch_total, ch_online, arch, uptime, rt 
                   FROM health 
                   WHERE server_id = ? 
                   ORDER BY ts DESC 
                   LIMIT 1""",
                (alert['server_id'],)
            ).fetchone()
            
            if health_row:
                alert_dict['health'] = dict(health_row)
            else:
                alert_dict['health'] = {
                    'cpu': '?',
                    'ch_online': '?',
                    'ch_total': '?',
                    'arch': '?',
                    'uptime': 0,
                    'rt': '?'
                }
            
            result.append(alert_dict)
        
        return result
    
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка получения алертов: {e}")
        import traceback
        traceback.print_exc()
        return []
    finally:
        conn.close()


def mark_alert_as_sent(alert_id, chat_id):
    """
    Помечает алерт как отправленный в telegram_logs
    
    Аргументы:
        alert_id: ID алерта из таблицы alerts
        chat_id: ID чата куда отправлено
    """
    conn = get_database_connection()
    
    try:
        conn.execute(
            """INSERT OR IGNORE INTO telegram_logs (ts, alert_key, chat_id) 
               VALUES (datetime('now', '+3 hours'), ?, ?)""",
            (str(alert_id), str(chat_id))
        )
        conn.commit()
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка маркировки алерта: {e}")
    finally:
        conn.close()


def get_enabled_chats():
    """
    Получает список всех активных получателей
    
    Возвращает:
        list[dict]: список чатов с настройками
    """
    conn = get_database_connection()
    
    try:
        chats = conn.execute(
            "SELECT * FROM telegram_chats WHERE enabled = 1"
        ).fetchall()
        
        return [dict(c) for c in chats]
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка получения чатов: {e}")
        return []
    finally:
        conn.close()


def is_telegram_enabled():
    """
    Проверяет, включены ли уведомления в настройках
    
    Возвращает:
        bool: True если enabled = '1'
    """
    conn = get_database_connection()
    
    try:
        row = conn.execute(
            "SELECT value FROM telegram_settings WHERE key = 'enabled'"
        ).fetchone()
        
        return row is not None and row[0] == '1'
    except Exception:
        return False
    finally:
        conn.close()


def cleanup_old_logs():
    """
    Удаляет старые записи из telegram_logs (старше 7 дней)
    """
    try:
        conn = get_database_connection()
        
        deleted = conn.execute(
            "DELETE FROM telegram_logs WHERE ts < datetime('now', '+3 hours', '-7 days')"
        ).rowcount
        
        conn.commit()
        
        if deleted > 0:
            print(f"[{datetime.now()}] 🧹 Очищено старых записей: {deleted}")
    
    except Exception as e:
        print(f"[{datetime.now()}] ⚠ Ошибка очистки: {e}")
    finally:
        conn.close()


# ============================================
# ГЛАВНЫЙ ЦИКЛ БОТА
# ============================================

def run_bot():
    """
    Основной бесконечный цикл работы бота
    """
    print(f"[{datetime.now()}] 🤖 Telegram Bot запускается...")
    print(f"[{datetime.now()}] 📁 База данных: {DB_PATH}")
    print(f"[{datetime.now()}] ⏱  Интервал проверки: {CHECK_INTERVAL} сек")
    
    cfg = get_config()
    
    if not cfg:
        print(f"[{datetime.now()}] ⚠ ВНИМАНИЕ: Конфигурация не найдена!")
        print(f"[{datetime.now()}]    Путь: {CONFIG_FILE}")
    elif not cfg['token']:
        print(f"[{datetime.now()}] ⚠ ВНИМАНИЕ: Токен не настроен!")
        print(f"[{datetime.now()}]    Файл: {CONFIG_FILE}")
    else:
        print(f"[{datetime.now()}] 🔑 Токен: {cfg['token'][:10]}...{cfg['token'][-4:]}")
    
    if cfg and cfg['proxy']:
        print(f"[{datetime.now()}] 🌐 Прокси: настроен")
    else:
        print(f"[{datetime.now()}] 🌐 Подключение: прямое")
    
    cleanup_old_logs()
    
    total_sent = 0
    checks = 0
    
    while True:
        try:
            checks += 1
            
            if not is_telegram_enabled():
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⏸ Уведомления отключены в настройках")
                time.sleep(CHECK_INTERVAL)
                continue
            
            cfg = get_config()
            if not cfg or not cfg['token']:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⚠ Токен не настроен")
                time.sleep(CHECK_INTERVAL)
                continue
            
            chats = get_enabled_chats()
            if not chats:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⚠ Нет активных получателей")
                time.sleep(CHECK_INTERVAL)
                continue
            
            alerts = get_new_alerts()
            
            for alert in alerts:
                text = format_alert_message(alert)
                sent_to = []
                
                for chat in chats:
                    chat_id = chat['chat_id']
                    
                    if alert['level'] == 'critical' and not chat.get('critical', True):
                        continue
                    if alert['level'] == 'warning' and not chat.get('warning', True):
                        continue
                    if alert['level'] == 'info' and not chat.get('info', False):
                        continue
                    
                    if send_telegram_message(chat_id, text):
                        mark_alert_as_sent(alert['id'], chat_id)
                        sent_to.append(str(chat_id))
                        total_sent += 1
                        time.sleep(0.05)
                
                if sent_to:
                    print(f"[{datetime.now()}] ✅ Отправлено: {alert['msg'][:60]}")
                    print(f"[{datetime.now()}]    Получатели: {', '.join(sent_to)}")
            
            if checks % 360 == 0:
                cleanup_old_logs()
        
        except KeyboardInterrupt:
            print(f"\n[{datetime.now()}] 🛑 Бот остановлен. Отправлено: {total_sent}")
            break
        except Exception as e:
            print(f"[{datetime.now()}] ❌ Ошибка: {e}")
            import traceback
            traceback.print_exc()
        
        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    run_bot()
TGBOTEOF

sed -i "s/CHECK_INTERVAL = 10/CHECK_INTERVAL = $CHECK_INTERVAL/" "$TGBOT_PY"

chmod +x "$TGBOT_PY"
chown www-data:www-data "$TGBOT_PY" 2>/dev/null || true

source "$INSTALL_DIR/venv/bin/activate"
$VENV_PYTHON -c "import ast; ast.parse(open('$TGBOT_PY').read()); print('  ✓ Синтаксис tg_bot.py корректен')"
deactivate

echo "  • Файл создан: $TGBOT_PY"
echo "    Размер: $(wc -c < "$TGBOT_PY") байт"
echo "    Строк: $(wc -l < "$TGBOT_PY")"
echo ""
echo -e "${GREEN}✅ Telegram бот создан${NC}"
echo ""

# ============================================
# ШАГ 4: ДОБАВЛЕНИЕ API В APP.PY
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [4/7] ИНТЕГРАЦИЯ API В APP.PY               ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if grep -q 'def api_telegram_chats\|TELEGRAM BOT API' "$APP_PY" 2>/dev/null; then
    echo "  ⚠ API для Telegram уже существует в app.py"
    echo "    Проверка: найдены существующие маршруты /api/telegram/"
    echo "    Пропускаем интеграцию API."
else
    echo "  • Добавление API endpoints в app.py..."
    
    source "$INSTALL_DIR/venv/bin/activate"
    $VENV_PYTHON << 'PYAPIEOF'
app_path = "/opt/trassir-monitor/app/app.py"

with open(app_path, 'r') as f:
    content = f.read()

api_block = '''

# ============================================
# TELEGRAM BOT API — УПРАВЛЕНИЕ УВЕДОМЛЕНИЯМИ
# ============================================

@app.route("/api/telegram/chats", methods=["GET", "POST", "PUT", "DELETE"])
def api_telegram_chats():
    """API для управления получателями Telegram уведомлений"""
    conn = get_db()
    if request.method == "GET":
        chats = conn.execute("SELECT * FROM telegram_chats ORDER BY id").fetchall()
        conn.close()
        return jsonify([dict(c) for c in chats])
    elif request.method == "POST":
        data = request.json
        chat_id = data.get("chat_id", "").strip()
        name = data.get("name", "").strip()
        if not chat_id:
            conn.close()
            return jsonify({"ok": 0, "error": "Не указан chat_id"}), 400
        try:
            conn.execute("INSERT INTO telegram_chats (chat_id, name) VALUES (?, ?)", (chat_id, name))
            conn.commit()
            conn.close()
            return jsonify({"ok": 1, "message": "Получатель добавлен"})
        except:
            conn.close()
            return jsonify({"ok": 0, "error": "Такой chat_id уже существует"}), 400
    elif request.method == "PUT":
        data = request.json
        cid = data.get("id")
        if cid:
            conn.execute(
                "UPDATE telegram_chats SET name=?, enabled=?, warning=?, critical=?, info=? WHERE id=?",
                (data.get("name",""), data.get("enabled",1), data.get("warning",1),
                 data.get("critical",1), data.get("info",0), cid)
            )
            conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки получателя обновлены"})
    elif request.method == "DELETE":
        cid = request.args.get("id")
        if cid:
            conn.execute("DELETE FROM telegram_chats WHERE id=?", (cid,))
            conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Получатель удалён"})


@app.route("/api/telegram/settings", methods=["GET", "POST"])
def api_telegram_settings():
    """API для управления настройками Telegram"""
    conn = get_db()
    if request.method == "GET":
        settings = dict(conn.execute("SELECT key, value FROM telegram_settings").fetchall())
        import configparser
        cfg = configparser.ConfigParser()
        cfg.read("/opt/trassir-monitor/config.ini")
        if "telegram" in cfg:
            token = cfg["telegram"].get("token", "")
            if token:
                settings["token_masked"] = token[:10] + "..." + token[-4:]
                settings["token_configured"] = True
            else:
                settings["token_configured"] = False
            settings["proxy_configured"] = bool(cfg["telegram"].get("proxy", ""))
            settings["monitor_url"] = cfg["telegram"].get("monitor_url", "")
        conn.close()
        return jsonify(settings)
    elif request.method == "POST":
        data = request.json
        for key, value in data.items():
            conn.execute(
                "INSERT OR REPLACE INTO telegram_settings (key, value) VALUES (?, ?)",
                (key, str(value))
            )
        conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки сохранены"})


@app.route("/api/telegram/test", methods=["POST"])
def api_telegram_test():
    """API для отправки тестового сообщения в Telegram"""
    from app.tg_bot import send_telegram_message, get_enabled_chats, format_test_message, get_config
    from datetime import datetime
    
    data = request.json or {}
    chat_id = data.get("chat_id")
    
    if not chat_id:
        chats = get_enabled_chats()
        if not chats:
            return jsonify({"ok": 0, "error": "Нет активных получателей"}), 400
        chat_id = chats[0]["chat_id"]
    
    cfg = get_config()
    monitor_url = cfg.get('monitor_url', '') if cfg else ''
    test_msg = format_test_message(monitor_url)
    
    ok = send_telegram_message(chat_id, test_msg)
    if ok:
        return jsonify({"ok": 1, "message": "Тестовое сообщение отправлено"})
    return jsonify({"ok": 0, "error": "Ошибка отправки. Проверьте токен и прокси."})
'''

marker = 'if __name__ != "__main__":'
if marker in content:
    content = content.replace(marker, api_block + '\n\n' + marker)
    with open(app_path, 'w') as f:
        f.write(content)
    print("    ✓ API endpoints добавлены в app.py")
else:
    print("    ❌ Маркер для вставки не найден в app.py")
PYAPIEOF

    if $VENV_PYTHON -c "import ast; ast.parse(open('$APP_PY').read()); print('    ✓ Синтаксис app.py корректен')" 2>&1; then
        echo "    ✓ Проверка синтаксиса пройдена"
    else
        echo "    ❌ Обнаружена синтаксическая ошибка!"
        echo "    Восстанавливаю оригинальный файл из бэкапа..."
        cp "$BACKUP_DIR/app.py.bak" "$APP_PY"
        echo "    ✓ Восстановлено. API не добавлен."
    fi
    deactivate
fi

echo ""
echo -e "${GREEN}✅ Интеграция API завершена${NC}"
echo ""

# ============================================
# ШАГ 5: ПОЛНАЯ ЗАМЕНА settings.html
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [5/7] ОБНОВЛЕНИЕ ВЕБ-ИНТЕРФЕЙСА            ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Выполняю ЧИСТУЮ замену settings.html..."

cat > "$SETTINGS_HTML" << 'HTMLFINAL'
{% extends "base.html" %}

{% block title %}Настройки — TRASSIR Monitor{% endblock %}

{% block content %}

<nav class="mb-4">
    <a href="/" class="btn btn-outline-light btn-sm">
        <i class="bi bi-arrow-left"></i> Назад на дашборд
    </a>
</nav>

<h2 class="mb-4"><i class="bi bi-gear"></i> Настройки системы</h2>

<div class="row g-4">
    <!-- Параметры мониторинга -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header">
                <i class="bi bi-sliders"></i> Параметры мониторинга
            </div>
            <div class="card-body">
                <form id="settingsForm">
                    <div class="mb-3">
                        <label class="form-label">Интервал опроса (секунд)</label>
                        <input type="number" class="form-control" name="poll_interval" 
                               value="{{ settings.poll_interval }}">
                        <small class="text-muted">Как часто опрашивать серверы TRASSIR</small>
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Хранение данных (дней)</label>
                        <input type="number" class="form-control" name="retention_days" 
                               value="{{ settings.retention_days }}">
                        <small class="text-muted">Сколько дней хранить историю и алерты</small>
                    </div>
                    
                    <div class="row">
                        <div class="col-6">
                            <label class="form-label">CPU Warning (%)</label>
                            <input type="number" class="form-control" name="cpu_warning" 
                                   value="{{ settings.cpu_warning }}">
                        </div>
                        <div class="col-6">
                            <label class="form-label">CPU Critical (%)</label>
                            <input type="number" class="form-control" name="cpu_critical" 
                                   value="{{ settings.cpu_critical }}">
                        </div>
                    </div>
                    
                    <div class="row mt-3">
                        <div class="col-6">
                            <label class="form-label">Архив Warning (дней)</label>
                            <input type="number" class="form-control" name="archive_warning_days" 
                                   value="{{ settings.archive_warning_days }}">
                        </div>
                        <div class="col-6">
                            <label class="form-label">Архив Critical (дней)</label>
                            <input type="number" class="form-control" name="archive_critical_days" 
                                   value="{{ settings.archive_critical_days }}">
                        </div>
                    </div>
                    
                    <button type="submit" class="btn btn-primary mt-3">
                        <i class="bi bi-check-lg"></i> Сохранить настройки
                    </button>
                </form>
            </div>
        </div>
    </div>
    
    <!-- Список серверов -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header">
                <i class="bi bi-hdd-stack"></i> Список серверов
            </div>
            <div class="card-body">
                {% if servers %}
                    <table class="table table-dark table-hover">
                        <thead>
                            <tr>
                                <th>Название</th>
                                <th>IP адрес</th>
                                <th>Порт</th>
                                <th>Действия</th>
                            </tr>
                        </thead>
                        <tbody>
                            {% for server in servers %}
                            <tr>
                                <td>{{ server.name }}</td>
                                <td>{{ server.ip }}</td>
                                <td>{{ server.port }}</td>
                                <td>
                                    <button class="btn btn-sm btn-danger" 
                                            onclick="if(confirm('Удалить сервер {{ server.name }}?'))fetch('/api/servers?id={{ server.id }}',{method:'DELETE'}).then(function(){location.reload()})">
                                        <i class="bi bi-trash"></i> Удалить
                                    </button>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                {% else %}
                    <p class="text-muted text-center py-3">Нет добавленных серверов</p>
                {% endif %}
            </div>
        </div>
    </div>

    <!-- ============================================ -->
    <!-- TELEGRAM УВЕДОМЛЕНИЯ                         -->
    <!-- ============================================ -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header d-flex justify-content-between align-items-center">
                <span><i class="bi bi-telegram"></i> Telegram уведомления</span>
                <span class="badge fs-6" id="tgStatusBadge">Загрузка...</span>
            </div>
            <div class="card-body">
                <style>
                    #tgNewChatId, #tgNewChatName {
                        color: #fff !important;
                        background: #1a1d27 !important;
                        border-color: #2d3239 !important;
                    }
                    #tgNewChatId::placeholder, #tgNewChatName::placeholder {
                        color: #6b7280 !important;
                    }
                </style>
                <div id="tgTokenInfo" class="mb-3 p-3 rounded" style="background: var(--bg);">
                    <div class="spinner-border spinner-border-sm" role="status"></div>
                    Загрузка информации о конфигурации...
                </div>
                
                <div class="mb-3">
                    <label class="form-label">👥 Получатели уведомлений:</label>
                    <div id="tgChatsList" class="mb-3" style="max-height: 200px; overflow-y: auto;">
                        <div class="text-center py-3">
                            <div class="spinner-border spinner-border-sm" role="status"></div>
                            <span class="ms-2" style="color: var(--muted);">Загрузка списка получателей...</span>
                        </div>
                    </div>
                    
                    <div class="input-group input-group-sm mb-2">
                        <input type="text" class="form-control" id="tgNewChatId" placeholder="Chat ID">
                        <input type="text" class="form-control" id="tgNewChatName" placeholder="Имя">
                        <button class="btn btn-primary" onclick="tgAddChat()"><i class="bi bi-plus-lg"></i></button>
                    </div>
                    <small class="text-muted">Узнать Chat ID: @userinfobot в Telegram</small>
                </div>
                
                <div class="form-check form-switch mb-3">
                    <input class="form-check-input" type="checkbox" id="tgEnabled" onchange="tgSaveSettings()">
                    <label class="form-check-label"><b>Включить уведомления в Telegram</b></label>
                </div>
                
                <div class="d-flex gap-2">
                    <button class="btn btn-outline-info btn-sm" onclick="tgTest()"><i class="bi bi-send"></i> Тест</button>
                    <button class="btn btn-outline-secondary btn-sm" onclick="tgRefresh()"><i class="bi bi-arrow-clockwise"></i> Обновить</button>
                </div>
                <div id="tgResult" class="mt-2" style="display: none;"></div>
            </div>
        </div>
    </div>
</div>

<script>
function tgRefresh(){tgLoadSettings();tgLoadChats();}
function tgLoadSettings(){
    fetch("/api/telegram/settings").then(function(r){return r.json()}).then(function(s){
        document.getElementById("tgEnabled").checked=(s.enabled==="1");
        var b=document.getElementById("tgStatusBadge");
        if(s.enabled==="1"&&s.token_configured){b.className="badge bg-success fs-6";b.textContent="✅ Активен";}
        else if(s.enabled==="1"){b.className="badge bg-warning fs-6";b.textContent="⚠ Нет токена";}
        else{b.className="badge bg-secondary fs-6";b.textContent="⏸ Выключен";}
        var i="";
        if(s.token_configured){
            i="<b>Токен:</b> <span style='color:var(--green)'>"+s.token_masked+"</span>";
            if(s.proxy_configured)i+=" | 🌐 Прокси настроен";
            if(s.monitor_url)i+="<br><b>Монитор:</b> "+s.monitor_url;
        }else{i="<span style='color:var(--red)'>❌ Токен не настроен</span>";}
        document.getElementById("tgTokenInfo").innerHTML=i;
    });
}
function tgLoadChats(){
    fetch("/api/telegram/chats").then(function(r){return r.json()}).then(function(chats){
        var h="";
        if(chats.length===0){h="<p style='color:var(--muted)'>Нет получателей</p>";}
        else{chats.forEach(function(c){
            h+="<div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;padding:6px 10px;background:var(--bg);border-radius:6px'>";
            h+="<div><span class='badge bg-"+(c.enabled?"success":"secondary")+" me-1'>"+(c.enabled?"вкл":"выкл")+"</span>";
            h+="<b>"+(c.name||"без имени")+"</b> <code>"+c.chat_id+"</code></div>";
            h+="<div>";
            h+="<button class='btn btn-sm btn-outline-info me-1' onclick='tgEditChat("+c.id+")' title='Редактировать'>✏</button>";
            h+="<button class='btn btn-sm btn-outline-danger' onclick='tgDeleteChat("+c.id+")' title='Удалить'>✕</button>";
            h+="</div></div>";
        });}
        document.getElementById("tgChatsList").innerHTML=h;
    });
}
function tgAddChat(){
    var id=document.getElementById("tgNewChatId").value.trim();
    var nm=document.getElementById("tgNewChatName").value.trim();
    if(!id){alert("Введите Chat ID");return;}
    fetch("/api/telegram/chats",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:id,name:nm})})
    .then(function(r){return r.json()}).then(function(d){
        if(d.ok){document.getElementById("tgNewChatId").value="";document.getElementById("tgNewChatName").value="";tgLoadChats();tgShowResult(d.message,"success");}
        else tgShowResult(d.error,"danger");
    });
}
function tgEditChat(dbId){
    fetch("/api/telegram/chats").then(function(r){return r.json()}).then(function(chats){
        var chat=chats.find(function(c){return c.id===dbId;});
        if(!chat)return;
        var newId=prompt("Новый Chat ID:",chat.chat_id);
        if(newId===null)return;
        var newName=prompt("Новое имя:",chat.name||"");
        if(newName===null)return;
        var data={id:dbId,name:newName||""};
        if(newId.trim()!==""&&newId.trim()!==chat.chat_id)data.chat_id=newId.trim();
        fetch("/api/telegram/chats",{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)})
        .then(function(r){return r.json()}).then(function(d){if(d.ok)tgLoadChats();else tgShowResult(d.error,"danger");});
    });
}
function tgDeleteChat(id){if(confirm("Удалить получателя?"))fetch("/api/telegram/chats?id="+id,{method:"DELETE"}).then(function(){tgLoadChats();});}
function tgSaveSettings(){
    fetch("/api/telegram/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({enabled:document.getElementById("tgEnabled").checked?"1":"0"})}).then(function(){tgLoadSettings();});
}
function tgTest(){
    var e=document.getElementById("tgResult");e.style.display="block";e.className="mt-2 alert alert-info";e.textContent="Отправка тестового сообщения...";
    fetch("/api/telegram/test",{method:"POST",headers:{"Content-Type":"application/json"},body:"{}"})
    .then(function(r){return r.json()}).then(function(d){
        e.className="mt-2 alert alert-"+(d.ok?"success":"danger");
        e.textContent=d.ok?d.message:d.error;
        setTimeout(function(){e.style.display="none"},5000);
    });
}
function tgShowResult(msg,type){
    var e=document.getElementById("tgResult");e.style.display="block";e.className="mt-2 alert alert-"+type;e.textContent=msg;
    setTimeout(function(){e.style.display="none"},5000);
}
tgRefresh();
</script>

{% endblock %}

{% block scripts %}
<script>
document.getElementById('settingsForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    var formData = new FormData(this);
    var data = Object.fromEntries(formData);
    var response = await fetch('/api/settings', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    if (response.ok) {
        alert('Настройки сохранены! Изменения вступят в силу при следующем опросе.');
    } else {
        alert('Ошибка при сохранении настроек');
    }
});
</script>
{% endblock %}
HTMLFINAL

echo "  ✓ settings.html полностью заменён"
echo ""

# ============================================
# ШАГ 6: SYSTEMD СЕРВИС
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [6/7] СОЗДАНИЕ SYSTEMD СЕРВИСА             ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

cat > "/etc/systemd/system/$SERVICE_BOT.service" << SERVEOF
[Unit]
Description=TRASSIR Monitor Telegram Bot
Documentation=https://github.com/trassir-monitor
After=$SERVICE_MAIN.service
Requires=$SERVICE_MAIN.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$VENV_PYTHON $TGBOT_PY
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/tgbot.log
StandardError=append:$LOG_DIR/tgbot-error.log

[Install]
WantedBy=multi-user.target
SERVEOF

touch "$LOG_DIR/tgbot.log" "$LOG_DIR/tgbot-error.log" 2>/dev/null
chown www-data:www-data "$LOG_DIR/tgbot.log" "$LOG_DIR/tgbot-error.log" 2>/dev/null || true

systemctl daemon-reload
systemctl enable "$SERVICE_BOT" 2>/dev/null

echo "  • Сервис создан: /etc/systemd/system/$SERVICE_BOT.service"
echo "  • Логи: $LOG_DIR/tgbot.log"
echo "  • Автозапуск: включён"

echo ""
echo -e "${GREEN}✅ Systemd сервис создан${NC}"
echo ""

# ============================================
# ШАГ 7: ЗАПУСК И ТЕСТИРОВАНИЕ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [7/7] ЗАПУСК И ТЕСТИРОВАНИЕ                ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Перезапуск TRASSIR Monitor..."
systemctl restart "$SERVICE_MAIN"
sleep 3

MAIN_STATUS=$(systemctl is-active "$SERVICE_MAIN" 2>/dev/null || echo "inactive")
echo "    Статус: $MAIN_STATUS"

echo "  • Запуск Telegram Bot..."
systemctl start "$SERVICE_BOT"
sleep 3

BOT_STATUS=$(systemctl is-active "$SERVICE_BOT" 2>/dev/null || echo "inactive")
echo "    Статус: $BOT_STATUS"

if [ "$BOT_STATUS" != "active" ]; then
    echo ""
    echo -e "  ${RED}❌ Бот не запустился!${NC}"
    echo "  Проверьте логи:"
    echo "    journalctl -u $SERVICE_BOT -n 20"
    echo "    tail -20 $LOG_DIR/tgbot-error.log"
fi

echo ""

# Отправка тестового сообщения
echo "  • Отправка тестового сообщения..."
source "$INSTALL_DIR/venv/bin/activate"

TEST_RESULT=$($VENV_PYTHON << 'PYEOF'
import sys, os
sys.path.insert(0, '/opt/trassir-monitor')
os.chdir('/opt/trassir-monitor')
from app.tg_bot import send_telegram_message, get_enabled_chats, format_test_message, get_config

chats = get_enabled_chats()
if not chats:
    print("NO_CHATS")
    sys.exit(0)

cfg = get_config()
monitor_url = cfg.get('monitor_url', '') if cfg else ''
msg = format_test_message(monitor_url)

if send_telegram_message(chats[0]['chat_id'], msg):
    print("OK")
else:
    print("FAIL")
PYEOF
)

deactivate

case "$TEST_RESULT" in
    OK)
        echo -e "  ${GREEN}✅ Тестовое сообщение отправлено успешно!${NC}"
        echo "     Проверьте Telegram — должно прийти сообщение."
        ;;
    NO_CHATS)
        echo -e "  ${YELLOW}⚠ Нет получателей для отправки теста${NC}"
        echo "     Добавьте получателей через веб-интерфейс /settings"
        ;;
    *)
        echo -e "  ${RED}❌ Тестовое сообщение не отправлено${NC}"
        echo ""
        echo "  Возможные причины:"
        echo "    1. Неправильный токен бота"
        echo "    2. Прокси не работает"
        echo "    3. Нет доступа к api.telegram.org"
        echo "    4. Неправильный Chat ID"
        echo ""
        echo "  Проверьте:"
        echo "    • Конфигурацию: $CONFIG_FILE"
        echo "    • Логи бота: tail -f $LOG_DIR/tgbot.log"
        echo "    • Логи ошибок: tail -20 $LOG_DIR/tgbot-error.log"
        ;;
esac

# ============================================
# ФИНАЛЬНЫЙ ВЫВОД
# ============================================
IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Telegram Bot — УСТАНОВЛЕН! 🎉               ║${NC}"
echo -e "${GREEN}║   v6.0 FINAL — Все функции активны            ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}🌐 Веб-управление:${NC}"
echo -e "   ${CYAN}http://${IP}:8080/settings${NC}"
echo -e "   (прокрутите вниз до карточки Telegram)"
echo ""
echo -e "${BOLD}📋 Управление ботом:${NC}"
echo -e "   Статус:      ${YELLOW}systemctl status $SERVICE_BOT${NC}"
echo -e "   Перезапуск:  ${YELLOW}systemctl restart $SERVICE_BOT${NC}"
echo -e "   Остановка:   ${YELLOW}systemctl stop $SERVICE_BOT${NC}"
echo -e "   Логи:        ${YELLOW}tail -f $LOG_DIR/tgbot.log${NC}"
echo -e "   Логи ошибок: ${YELLOW}tail -f $LOG_DIR/tgbot-error.log${NC}"
echo ""
echo -e "${BOLD}📁 Файлы:${NC}"
echo -e "   Конфигурация: ${CYAN}$CONFIG_FILE${NC} (chmod 600)"
echo -e "   Код бота:     ${CYAN}$TGBOT_PY${NC}"
echo -e "   Бэкап:        ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "${BOLD}✅ Возможности веб-интерфейса:${NC}"
echo -e "   • Просмотр статуса токена и прокси"
echo -e "   • Добавление и удаление получателей"
echo -e "   • ✏ Редактирование Chat ID и имени"
echo -e "   • Включение и выключение уведомлений"
echo -e "   • Отправка тестового сообщения"
echo ""
echo -e "${BOLD}📱 Формат уведомлений в Telegram:${NC}"
echo -e "   📷 ОТВАЛ КАМЕР — с указанием имён"
echo -e "   🔥 ВЫСОКАЯ НАГРУЗКА CPU"
echo -e "   💾 ПРОБЛЕМА С АРХИВОМ"
echo -e "   💿 ОШИБКА ДИСКОВ"
echo -e "   🔴 КРИТИЧЕСКИЙ АЛЕРТ"
echo -e "   Для каждого: состояние сервера, uptime, отклик"
echo ""
echo -e "${BOLD}🛡 Защита от спама:${NC}"
echo -e "   • 1 проблема = 1 сообщение"
echo -e "   • Бот проверяет БД перед отправкой"
echo -e "   • Повторов нет"
echo -e "   • Новый алерт после восстановления = новое сообщение"
echo ""
echo -e "${BOLD}🔧 Изменение токена или прокси:${NC}"
echo -e "   1. Отредактируйте: ${YELLOW}nano $CONFIG_FILE${NC}"
echo -e "   2. Перезапустите: ${YELLOW}systemctl restart $SERVICE_BOT${NC}"
echo ""
