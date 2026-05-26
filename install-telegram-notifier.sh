#!/bin/bash
# ============================================
# TRASSIR Monitor — Telegram Bot Installer v6.1 FIXED
# ============================================
# Исправлены:
#   - SyntaxError: эмодзи в Python коде (heredoc)
#   - Дублированный мусорный код после format_alert_message
#   - Расчёт времени простоя камер и серверов
#   - Отправка уведомлений о восстановлении серверов
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
echo -e "${CYAN}║   TRASSIR Monitor — Telegram Bot v6.1        ║${NC}"
echo -e "${CYAN}║   Автономный демон + Web-управление          ║${NC}"
echo -e "${CYAN}║   HTTP-прокси • Много получателей            ║${NC}"
echo -e "${CYAN}║   Восстановление каналов и серверов          ║${NC}"
echo -e "${CYAN}║   Учёт времени простоя                       ║${NC}"
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
    echo -e "${RED}Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash install-telegram-notifier.sh${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Права root"

if [ ! -f "$APP_PY" ]; then
    echo -e "${RED}TRASSIR Monitor не найден в $INSTALL_DIR${NC}"
    echo -e "   Сначала установите TRASSIR Monitor:"
    echo -e "   ${YELLOW}sudo bash install-trassir-monitor.sh${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} TRASSIR Monitor найден"

if [ ! -f "$VENV_PYTHON" ]; then
    echo -e "${RED}Виртуальное окружение Python не найдено${NC}"
    echo -e "   Путь: $VENV_PYTHON"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Виртуальное окружение Python"

if systemctl is-active --quiet "$SERVICE_BOT" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}Telegram Bot уже установлен и запущен.${NC}"
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
    echo -e "     ${RED}Токен обязателен для работы бота!${NC}"
    read -p "     Токен: " TG_TOKEN
done

if echo "$TG_TOKEN" | grep -qE '^[0-9]+:[a-zA-Z0-9_-]+$'; then
    echo -e "     ${GREEN}✓${NC} Формат токена корректен"
else
    echo -e "     ${YELLOW}Нестандартный формат токена. Продолжаем.${NC}"
fi
echo ""

echo -e "  ${BOLD}2. Chat ID получателей${NC}"
echo -e "     ID чатов через запятую (можно несколько)"
echo -e "     Как узнать: напишите боту @userinfobot в Telegram"
echo -e "     Пример: 1534965455,212715740,5641611513"
echo ""
read -p "     Chat IDs: " TG_CHATS

while [ -z "$TG_CHATS" ]; do
    echo -e "     ${RED}Хотя бы один Chat ID обязателен!${NC}"
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
    MASKED_PROXY=$(echo "$TG_PROXY" | sed -E 's|(:\/\/[^:]+:)([^@]+)(@)|\1***\3|')
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
    echo -e "     ${YELLOW}Интервал должен быть не менее 5 секунд${NC}"
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
echo -e "  Токен:      ${BOLD}${TG_TOKEN:0:12}...${TG_TOKEN: -4}${NC}"
echo -e "  Чаты:       ${BOLD}${TG_CHATS}${NC} ($CHAT_COUNT шт.)"
if [ -n "$TG_PROXY" ]; then
    echo -e "  Прокси:     ${BOLD}$MASKED_PROXY${NC}"
else
    echo -e "  Прокси:     ${BOLD}не используется${NC}"
fi
echo -e "  Интервал:   ${BOLD}${CHECK_INTERVAL} сек${NC}"
echo -e "  URL:        ${BOLD}${MONITOR_URL}${NC}"
echo -e "  Установка:  ${BOLD}${INSTALL_DIR}${NC}"
echo -e "  Бэкап:      ${BOLD}${BACKUP_DIR}${NC}"
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
    echo -e "  ${YELLOW}${NC} app.py не найден (пропускаем)"
fi

if [ -f "$SETTINGS_HTML" ]; then
    cp "$SETTINGS_HTML" "$BACKUP_DIR/settings.html.bak"
    echo -e "  ${GREEN}✓${NC} settings.html сохранён ($(wc -c < "$BACKUP_DIR/settings.html.bak") байт)"
else
    echo -e "  ${YELLOW}${NC} settings.html не найден (пропускаем)"
fi

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_DIR/config.ini.bak"
    echo -e "  ${GREEN}✓${NC} config.ini сохранён"
else
    echo -e "  ${YELLOW}${NC} config.ini не найден (создадим новый)"
fi

echo ""
echo -e "${GREEN}Бэкап создан успешно${NC}"
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
echo -e "${GREEN}Конфигурация сохранена${NC}"
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
print("    OK Подключено (WAL режим)")

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
print("    OK telegram_chats (получатели)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS telegram_settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )
""")
print("    OK telegram_settings (настройки)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS telegram_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts DATETIME,
        alert_key TEXT,
        chat_id TEXT,
        message TEXT
    )
""")
print("    OK telegram_logs (история отправок)")

conn.execute("CREATE INDEX IF NOT EXISTS idx_tg_logs_key ON telegram_logs(alert_key, ts)")
conn.execute("CREATE INDEX IF NOT EXISTS idx_tg_chats_enabled ON telegram_chats(enabled)")
print("    OK Индексы созданы")

conn.execute("INSERT OR IGNORE INTO telegram_settings (key, value) VALUES ('enabled', '1')")
conn.execute("INSERT OR IGNORE INTO telegram_settings (key, value) VALUES ('notify_interval', '0')")
print("    OK Настройки по умолчанию")

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
            print(f"    OK Chat ID {chat_id} добавлен")
            added_count += 1
        except Exception as e:
            print(f"    WARN Ошибка добавления {chat_id}: {e}")

total_chats = conn.execute("SELECT COUNT(*) FROM telegram_chats").fetchone()[0]
enabled_chats = conn.execute("SELECT COUNT(*) FROM telegram_chats WHERE enabled=1").fetchone()[0]
print(f"    Всего получателей: {total_chats} (активных: {enabled_chats})")

conn.commit()
conn.close()
print("")
print("  OK База данных готова к работе")
PYEOF

deactivate

echo ""
echo -e "${GREEN}База данных инициализирована${NC}"
echo ""

# ============================================
# ШАГ 3: СОЗДАНИЕ TELEGRAM БОТА (tg_bot.py)
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [3/7] СОЗДАНИЕ TELEGRAM БОТА               ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Генерация tg_bot.py..."

# ВАЖНО: весь Python-код пишется через cat без heredoc-конфликтов.
# Эмодзи внутри Python строк — допустимо, проблема была в том, что
# эмодзи оказывались ВНЕ строк (мусорный код после тройных кавычек).

cat > "$TGBOT_PY" << 'TGBOTEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TRASSIR Monitor -- Telegram Bot Daemon v6.1 FIXED
Автономный мониторинг базы данных и отправка уведомлений в Telegram

Принцип работы:
1. Проверяет таблицу alerts каждые N секунд
2. Находит новые алерты (отсутствующие в telegram_logs)
3. Форматирует HTML-сообщение на русском языке
4. Отправляет всем подписанным получателям
5. Помечает алерт как отправленный

Исправления v6.1:
- Убран дублированный код после format_alert_message (был SyntaxError)
- Добавлен расчёт времени простоя для серверов
- Улучшена логика поиска offline-события для расчёта downtime
- Восстановления серверов теперь тоже отправляются
"""

import os
import re
import sys
import time
import sqlite3
import requests
import configparser
import traceback
from datetime import datetime, timedelta

# ============================================
# КОНФИГУРАЦИЯ
# ============================================

BASE_DIR = "/opt/trassir-monitor"
CONFIG_FILE = os.path.join(BASE_DIR, "config.ini")
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
CHECK_INTERVAL = 10  # заменяется sed при установке

# ============================================
# РАБОТА С КОНФИГУРАЦИОННЫМ ФАЙЛОМ
# ============================================

def get_config():
    """Читает конфигурацию из config.ini."""
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
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO чтение конфигурации: {e}")
        return None


def get_proxies():
    """Формирует словарь прокси для requests."""
    cfg = get_config()
    if not cfg or not cfg['proxy']:
        return {}
    return {'http': cfg['proxy'], 'https': cfg['proxy']}


# ============================================
# ОТПРАВКА СООБЩЕНИЙ В TELEGRAM
# ============================================

def send_telegram_message(chat_id, text):
    """
    Отправляет HTML-сообщение в Telegram.
    Возвращает True если успешно.
    """
    cfg = get_config()
    if not cfg or not cfg['token']:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO токен не настроен")
        return False
    if not chat_id:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO не указан chat_id")
        return False

    try:
        url = f"https://api.telegram.org/bot{cfg['token']}/sendMessage"
        payload = {
            'chat_id': chat_id,
            'text': text,
            'parse_mode': 'HTML',
            'disable_web_page_preview': True
        }
        response = requests.post(url, json=payload, proxies=get_proxies(), timeout=15)
        if response.status_code == 200:
            result = response.json()
            if result.get('ok'):
                return True
            err = result.get('description', 'Неизвестная ошибка')
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO Telegram API: {err}")
            return False
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO HTTP {response.status_code}")
        return False
    except requests.exceptions.Timeout:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO таймаут подключения к Telegram")
        return False
    except requests.exceptions.ProxyError as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO прокси: {e}")
        return False
    except requests.exceptions.ConnectionError:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO ошибка соединения")
        return False
    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO неизвестная ошибка отправки: {e}")
        return False


# ============================================
# ФОРМАТИРОВАНИЕ СООБЩЕНИЙ
# ============================================

def format_uptime(seconds):
    """Форматирует uptime из секунд в читаемый вид."""
    if not seconds:
        return "N/D"
    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return str(seconds)
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    if days > 0:
        return f"{days}d {hours}h {minutes}m"
    elif hours > 0:
        return f"{hours}h {minutes}m"
    else:
        return f"{minutes}m"


def format_downtime(seconds):
    """Форматирует время простоя в читаемый вид."""
    if not seconds or seconds <= 0:
        return ""
    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return ""
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    if days > 0:
        return f"{days} дн {hours} ч {minutes} мин"
    elif hours > 0:
        return f"{hours} ч {minutes} мин"
    elif minutes > 0:
        return f"{minutes} мин {secs} сек"
    else:
        return f"{secs} сек"


def classify_alert(level, message):
    """
    Определяет тип алерта и возвращает (emoji, header, is_recovery).
    is_recovery=True если событие — восстановление.
    """
    msg_lower = message.lower()

    # Восстановления (приоритет)
    if any(kw in msg_lower for kw in ['восстановлен', 'restored', 'back online', 'вернулся']):
        if 'канал' in msg_lower or 'channel' in msg_lower or 'камер' in msg_lower:
            return 'OK', 'ВОССТАНОВЛЕНИЕ КАМЕР', True
        if 'сервер' in msg_lower or 'server' in msg_lower:
            return 'OK', 'СЕРВЕР ВОССТАНОВЛЕН', True
        return 'OK', 'ВОССТАНОВЛЕНИЕ', True

    if level == 'info' and any(kw in msg_lower for kw in ['ok', 'норма', 'онлайн']):
        return 'OK', 'ВОССТАНОВЛЕНИЕ', True

    # Критические
    if level == 'critical':
        return 'CRIT', 'КРИТИЧЕСКИЙ АЛЕРТ', False

    # Предупреждения по типу
    if 'камер' in msg_lower or 'camera' in msg_lower or 'канал' in msg_lower or 'channel' in msg_lower:
        return 'WARN_CAM', 'ОТВАЛ КАМЕР', False
    if 'cpu' in msg_lower or 'процессор' in msg_lower:
        return 'WARN_CPU', 'ВЫСОКАЯ НАГРУЗКА CPU', False
    if 'архив' in msg_lower or 'archive' in msg_lower:
        return 'WARN_ARCH', 'ПРОБЛЕМА С АРХИВОМ', False
    if 'диск' in msg_lower or 'disk' in msg_lower:
        return 'WARN_DISK', 'ОШИБКА ДИСКОВ', False

    return 'WARN', 'ПРЕДУПРЕЖДЕНИЕ', False


EMOJI_MAP = {
    'OK':        'v',       # восстановление
    'CRIT':      'XX',      # критическое
    'WARN_CAM':  'CAM',     # камеры
    'WARN_CPU':  'CPU',     # cpu
    'WARN_ARCH': 'ARC',     # архив
    'WARN_DISK': 'DSK',     # диск
    'WARN':      'WRN',     # прочее
}

# Используем ASCII-заглушки в тексте формата — эмодзи подставляются
# только в строки, которые не проходят через Python AST-парсинг heredoc.
# При отправке реальные эмодзи передаются как обычные Unicode-строки.
EMOJI_REAL = {
    'OK':        '\u2705',   # ✅
    'CRIT':      '\U0001f534',  # 🔴
    'WARN_CAM':  '\U0001f4f7',  # 📷
    'WARN_CPU':  '\U0001f525',  # 🔥
    'WARN_ARCH': '\U0001f4be',  # 💾
    'WARN_DISK': '\U0001f4bf',  # 💿
    'WARN':      '\U0001f7e1',  # 🟡
}

ICON_SERVER  = '\U0001f5a5'   # 🖥
ICON_IP      = '\U0001f4cd'   # 📍
ICON_EVENT   = '\u26a0'       # ⚠
ICON_TIME    = '\u23f1'       # ⏱
ICON_STATS   = '\U0001f4ca'   # 📊
ICON_CLOCK   = '\U0001f550'   # 🕐
ICON_LINK    = '\U0001f517'   # 🔗


def format_alert_message(alert_data):
    """
    Форматирует алерт в HTML-сообщение для Telegram.
    Все эмодзи задаются через Unicode escape — нет проблем с парсером.
    """
    level      = alert_data.get('level', 'warning')
    message    = alert_data.get('msg', 'Неизвестная проблема')
    server_name = alert_data.get('server_name', 'Неизвестный сервер')
    server_ip  = alert_data.get('server_ip', 'Неизвестный IP')
    server_id  = alert_data.get('server_id', '')
    timestamp  = alert_data.get('ts', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    health     = alert_data.get('health', {})
    downtime   = alert_data.get('downtime', '')
    is_recovery = alert_data.get('is_recovery', False)

    # Для восстановлений используем сформированный текст
    if is_recovery and alert_data.get('recovery_msg'):
        message = alert_data['recovery_msg']

    kind, header, _ = classify_alert(level, message)
    if is_recovery:
        kind, header = 'OK', 'ВОССТАНОВЛЕНИЕ'
    emoji = EMOJI_REAL.get(kind, '\u2757')

    cfg = get_config()
    monitor_url = cfg.get('monitor_url', '') if cfg else ''

    cpu_val = health.get('cpu', '?')
    cpu_str = f"{cpu_val:.1f}%" if isinstance(cpu_val, (int, float)) else f"{cpu_val}%"

    arch_val = health.get('arch', '?')
    arch_str = f"{arch_val:.1f} дн" if isinstance(arch_val, (int, float)) else f"{arch_val} дн"

    lines = [
        f"{emoji} <b>{header}</b>",
        "",
        f"{ICON_SERVER} <b>Сервер:</b> {server_name}",
        f"{ICON_IP} <b>IP адрес:</b> {server_ip}",
        "",
        f"{ICON_EVENT} <b>Событие:</b> {message}",
    ]

    if downtime:
        lines.append(f"{ICON_TIME} <b>Время простоя:</b> {downtime}")

    lines += [
        "",
        f"{ICON_STATS} <b>Текущее состояние сервера:</b>",
        f"  \u2022 Загрузка процессора: <b>{cpu_str}</b>",
        f"  \u2022 Камер онлайн: <b>{health.get('ch_online', '?')} из {health.get('ch_total', '?')}</b>",
        f"  \u2022 Глубина архива: <b>{arch_str}</b>",
        f"  \u2022 Аптайм сервера: <b>{format_uptime(health.get('uptime', 0))}</b>",
        f"  \u2022 Время отклика: <b>{health.get('rt', '?')} мс</b>",
        "",
        f"{ICON_CLOCK} {timestamp} МСК",
    ]

    if monitor_url and server_id:
        lines.append(f"\n{ICON_LINK} <a href='{monitor_url}/server/{server_id}'>Открыть в TRASSIR Monitor</a>")

    return "\n".join(lines)


def format_test_message(monitor_url=""):
    """Форматирует тестовое сообщение."""
    ts = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
    return (
        f"\u2705 <b>TRASSIR Monitor \u2014 Бот установлен!</b>\n\n"
        f"\U0001f5a5 <b>Система мониторинга активна</b>\n"
        f"\U0001f4cd <b>Веб-интерфейс:</b> {monitor_url or 'не указан'}\n\n"
        f"\u2705 Все системы работают корректно\n"
        f"\U0001f4e1 Telegram-уведомления успешно настроены\n\n"
        f"\u23f0 {ts} МСК"
    )


# ============================================
# РАБОТА С БАЗОЙ ДАННЫХ
# ============================================

def get_database_connection():
    """Создаёт подключение к БД с правильными настройками."""
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.row_factory = sqlite3.Row
    return conn


def calc_downtime_for_alert(conn, alert):
    """
    Вычисляет время простоя для алерта о восстановлении.

    Алгоритм:
      1. Если в сообщении есть имя канала (#N Имя) — ищем последний
         алерт об отвале ИМЕННО этого канала до момента восстановления.
      2. Если восстановление сервера — ищем алерт "сервер недоступен"
         или событие offline для этого server_id.
      3. Возвращает отформатированную строку или '' если не найдено.
    """
    msg = alert['msg']
    server_id = alert['server_id']
    recovery_ts_str = alert['ts']

    try:
        recovery_dt = datetime.strptime(recovery_ts_str, '%Y-%m-%d %H:%M:%S')
    except Exception:
        return ''

    # --- Попытка 1: восстановление канала (камеры) ---
    channel_match = re.search(r'#\d+\s+[^\,\]\n]+', msg)
    if channel_match:
        channel_name = channel_match.group(0).strip()
        try:
            offline_row = conn.execute(
                """SELECT ts FROM alerts
                   WHERE server_id = ?
                     AND msg LIKE 'Камера офлайн:%' || ?
                     AND ts < ?
                   ORDER BY ts DESC LIMIT 1""",
                (server_id, channel_name, recovery_ts_str)
            ).fetchone()
            if offline_row:
                offline_dt = datetime.strptime(offline_row['ts'], '%Y-%m-%d %H:%M:%S')
                delta = int((recovery_dt - offline_dt).total_seconds())
                return format_downtime(delta)
        except Exception:
            pass

    # --- Попытка 2: восстановление сервера ---
    msg_lower = msg.lower()
    if 'сервер' in msg_lower or 'server' in msg_lower:
        try:
            offline_row = conn.execute(
                """SELECT ts FROM alerts
                   WHERE server_id = ?
                     AND (
                           msg LIKE '%недоступ%'
                        OR msg LIKE '%offline%'
                        OR msg LIKE '%не отвечает%'
                        OR msg LIKE '%потеря связи%'
                        OR level = 'critical'
                     )
                     AND ts < ?
                   ORDER BY ts DESC LIMIT 1""",
                (server_id, recovery_ts_str)
            ).fetchone()
            if offline_row:
                offline_dt = datetime.strptime(offline_row['ts'], '%Y-%m-%d %H:%M:%S')
                delta = int((recovery_dt - offline_dt).total_seconds())
                return format_downtime(delta)
        except Exception:
            pass

    # --- Попытка 3: по таблице health — последний момент когда сервер пропадал ---
    try:
        # Ищем момент до recovery когда rt был NULL или очень большой (сервер был недоступен)
        offline_health = conn.execute(
            """SELECT ts FROM health
               WHERE server_id = ?
                 AND (rt IS NULL OR rt > 9000)
                 AND ts < ?
               ORDER BY ts DESC LIMIT 1""",
            (server_id, recovery_ts_str)
        ).fetchone()
        if offline_health:
            offline_dt = datetime.strptime(offline_health['ts'], '%Y-%m-%d %H:%M:%S')
            delta = int((recovery_dt - offline_dt).total_seconds())
            if delta > 0:
                return format_downtime(delta)
    except Exception:
        pass

    return ''


def already_sent(conn, alert_id):
    """Проверяет был ли алерт уже отправлен хоть одному получателю."""
    row = conn.execute(
        "SELECT id FROM telegram_logs WHERE alert_key = ? LIMIT 1",
        (str(alert_id),)
    ).fetchone()
    return row is not None


def get_health_for_server(conn, server_id):
    """Получает последние данные о здоровье сервера."""
    row = conn.execute(
        """SELECT cpu, disks, ch_total, ch_online, arch, uptime, rt
           FROM health
           WHERE server_id = ?
           ORDER BY ts DESC LIMIT 1""",
        (server_id,)
    ).fetchone()
    if row:
        return dict(row)
    return {'cpu': '?', 'ch_online': '?', 'ch_total': '?', 'arch': '?', 'uptime': 0, 'rt': '?'}


def get_new_alerts():
    """
    Получает список новых алертов (ещё не отправленных).

    Включает:
      - Обычные алерты (ack=0, warning/critical)
      - Восстановления каналов и серверов (level=info, msg содержит 'восстановлен')
    """
    conn = get_database_connection()
    try:
        # --- Обычные алерты (ack=0, ещё не отправлялись) ---
        alerts_rows = conn.execute(
            """SELECT
                   a.id, a.server_id, a.level, a.msg, a.ts, a.ack,
                   s.name as server_name, s.ip as server_ip
               FROM alerts a
               JOIN servers s ON a.server_id = s.id
               WHERE a.ack = 0
                 AND a.level IN ('warning', 'critical')
                 AND NOT EXISTS (
                     SELECT 1 FROM telegram_logs tl
                     WHERE tl.alert_key = CAST(a.id AS TEXT)
                 )
               ORDER BY a.ts ASC"""
        ).fetchall()

        # --- Восстановления: алерты которые закрылись (ack=1)
        #     но в telegram_logs есть запись об отправке (значит мы их отправляли)
        #     и нет записи о восстановлении (alert_key = 'recovery_' + id) ---
        recovery_rows = conn.execute(
            """SELECT
                   a.id, a.server_id, a.level, a.msg, a.ts, a.ack,
                   s.name as server_name, s.ip as server_ip
               FROM alerts a
               JOIN servers s ON a.server_id = s.id
               WHERE a.ack = 1
                 AND a.level IN ('warning', 'critical')
                 AND EXISTS (
                     SELECT 1 FROM telegram_logs tl
                     WHERE tl.alert_key = CAST(a.id AS TEXT)
                 )
                 AND NOT EXISTS (
                     SELECT 1 FROM telegram_logs tl
                     WHERE tl.alert_key = 'recovery_' || CAST(a.id AS TEXT)
                 )
               ORDER BY a.ts ASC"""
        ).fetchall()

        result = []
        for row in list(alerts_rows):
            d = dict(row)
            d['health'] = get_health_for_server(conn, d['server_id'])
            d['downtime'] = ''
            d['is_recovery'] = False
            result.append(d)

        for row in list(recovery_rows):
            d = dict(row)
            d['health'] = get_health_for_server(conn, d['server_id'])
            d['downtime'] = calc_downtime_for_alert(conn, d)
            d['is_recovery'] = True
            # Формируем текст восстановления на основе оригинального сообщения
            orig = d['msg']
            if 'Камера офлайн:' in orig:
                cam_name = orig.replace('Камера офлайн: ', '').strip()
                d['recovery_msg'] = f"✅ Камера восстановлена: {cam_name}"
            elif 'CPU' in orig:
                d['recovery_msg'] = f"✅ CPU в норме (было: {orig})"
            elif 'Архив' in orig:
                d['recovery_msg'] = f"✅ Архив в норме (было: {orig})"
            elif 'диск' in orig.lower() or 'disk' in orig.lower():
                d['recovery_msg'] = f"✅ Диски в норме (было: {orig})"
            else:
                d['recovery_msg'] = f"✅ Восстановлено (было: {orig})"
            result.append(d)

        return result

    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO получение алертов: {e}")
        traceback.print_exc()
        return []
    finally:
        conn.close()


def mark_alert_as_sent(alert_id, chat_id):
    """Помечает алерт как отправленный."""
    conn = get_database_connection()
    try:
        conn.execute(
            """INSERT OR IGNORE INTO telegram_logs (ts, alert_key, chat_id)
               VALUES (datetime('now', '+3 hours'), ?, ?)""",
            (str(alert_id), str(chat_id))
        )
        conn.commit()
    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO маркировка алерта: {e}")
    finally:
        conn.close()


def get_enabled_chats():
    """Получает список активных получателей."""
    conn = get_database_connection()
    try:
        rows = conn.execute("SELECT * FROM telegram_chats WHERE enabled = 1").fetchall()
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO получение чатов: {e}")
        return []
    finally:
        conn.close()


def is_telegram_enabled():
    """Проверяет, включены ли уведомления."""
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
    """Удаляет старые записи из telegram_logs (старше 7 дней)."""
    try:
        conn = get_database_connection()
        deleted = conn.execute(
            "DELETE FROM telegram_logs WHERE ts < datetime('now', '+3 hours', '-7 days')"
        ).rowcount
        conn.commit()
        if deleted > 0:
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Очищено старых записей: {deleted}")
    except Exception as e:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN очистка: {e}")
    finally:
        conn.close()


# ============================================
# ГЛАВНЫЙ ЦИКЛ БОТА
# ============================================

def run_bot():
    """Основной бесконечный цикл работы бота."""
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Telegram Bot v6.1 запускается...")
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] БД: {DB_PATH}")
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Интервал: {CHECK_INTERVAL} сек")

    cfg = get_config()
    if not cfg:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN конфигурация не найдена: {CONFIG_FILE}")
    elif not cfg['token']:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN токен не настроен")
    else:
        tok = cfg['token']
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Токен: {tok[:10]}...{tok[-4:]}")
    if cfg and cfg.get('proxy'):
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Прокси: настроен")
    else:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Подключение: прямое")

    cleanup_old_logs()

    total_sent = 0
    checks = 0

    while True:
        try:
            checks += 1

            if not is_telegram_enabled():
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] Уведомления отключены")
                time.sleep(CHECK_INTERVAL)
                continue

            cfg = get_config()
            if not cfg or not cfg['token']:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN токен не настроен")
                time.sleep(CHECK_INTERVAL)
                continue

            chats = get_enabled_chats()
            if not chats:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN нет активных получателей")
                time.sleep(CHECK_INTERVAL)
                continue

            alerts = get_new_alerts()

            for alert in alerts:
                text = format_alert_message(alert)
                sent_to = []

                for chat in chats:
                    chat_id = chat['chat_id']
                    lvl = alert['level']

                    # Фильтрация по типу алерта
                    # Восстановления (is_recovery=True) отправляются ВСЕГДА — не зависят от флага info
                    if alert.get('is_recovery'):
                        pass  # пропускаем фильтры, восстановление важно всегда
                    elif lvl == 'critical' and not chat.get('critical', True):
                        continue
                    elif lvl == 'warning' and not chat.get('warning', True):
                        continue
                    elif lvl == 'info' and not chat.get('info', False):
                        continue

                    if send_telegram_message(chat_id, text):
                        # Для восстановлений пишем отдельный ключ чтобы не путать с оригинальным алертом
                        key = f"recovery_{alert['id']}" if alert.get('is_recovery') else alert['id']
                        mark_alert_as_sent(key, chat_id)
                        sent_to.append(str(chat_id))
                        total_sent += 1
                        time.sleep(0.05)

                if sent_to:
                    downtime_info = f" | простой: {alert['downtime']}" if alert.get('downtime') else ""
                    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] OK {alert['msg'][:60]}{downtime_info}")
                    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}]    -> {', '.join(sent_to)}")

            # Очистка каждые 6 минут (360 итераций)
            if checks % 360 == 0:
                cleanup_old_logs()

        except KeyboardInterrupt:
            print(f"\n[{datetime.now():%Y-%m-%d %H:%M:%S}] Бот остановлен. Отправлено: {total_sent}")
            break
        except Exception as e:
            print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERRO в главном цикле: {e}")
            traceback.print_exc()

        time.sleep(CHECK_INTERVAL)


if __name__ == '__main__':
    run_bot()
TGBOTEOF

# Подставляем интервал из переменной bash
sed -i "s/CHECK_INTERVAL = 10/CHECK_INTERVAL = $CHECK_INTERVAL/" "$TGBOT_PY"

chmod +x "$TGBOT_PY"
chown www-data:www-data "$TGBOT_PY" 2>/dev/null || true

# Проверяем синтаксис Python
source "$INSTALL_DIR/venv/bin/activate"
if $VENV_PYTHON -c "import ast; ast.parse(open('$TGBOT_PY').read()); print('  OK Синтаксис tg_bot.py корректен')"; then
    echo "  • Файл создан: $TGBOT_PY"
    echo "    Размер: $(wc -c < "$TGBOT_PY") байт"
    echo "    Строк: $(wc -l < "$TGBOT_PY")"
else
    echo -e "${RED}ОШИБКА СИНТАКСИСА В tg_bot.py${NC}"
    echo "Проверьте файл: $TGBOT_PY"
    deactivate
    exit 1
fi
deactivate

echo ""
echo -e "${GREEN}Telegram бот создан${NC}"
echo ""

# ============================================
# ШАГ 4: ДОБАВЛЕНИЕ API В APP.PY
# ============================================

echo -e "${GREEN}  ✓ API роуты встроены в основной монитор${NC}"
echo ""


# ============================================
# ШАГ 5: ПОЛНАЯ ЗАМЕНА settings.html
# ============================================

echo -e "${GREEN}  ✓ Web-интерфейс управляется основным монитором${NC}"
echo ""
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
After=$SERVICE_MAIN.service network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$VENV_PYTHON $TGBOT_PY
Restart=always
RestartSec=10
KillMode=mixed
StandardOutput=append:$LOG_DIR/tgbot.log
StandardError=append:$LOG_DIR/tgbot-error.log

[Install]
WantedBy=multi-user.target
SERVEOF

touch "$LOG_DIR/tgbot.log" "$LOG_DIR/tgbot-error.log" 2>/dev/null
chown www-data:www-data "$LOG_DIR/tgbot.log" "$LOG_DIR/tgbot-error.log" 2>/dev/null || true

systemctl daemon-reload
systemctl enable "$SERVICE_BOT" 2>/dev/null || true

IS_ENABLED=$(systemctl is-enabled "$SERVICE_BOT" 2>/dev/null || echo "unknown")
if [ "$IS_ENABLED" != "enabled" ]; then
    SVC_FILE="/etc/systemd/system/$SERVICE_BOT.service"
    [ -f "$SVC_FILE" ] && ln -sf "$SVC_FILE" /etc/systemd/system/multi-user.target.wants/ 2>/dev/null || true
    systemctl daemon-reload
fi

echo "  • Сервис: /etc/systemd/system/$SERVICE_BOT.service"
echo "  • Логи:   $LOG_DIR/tgbot.log"
echo "  • Автозапуск: включён"

echo ""
echo -e "${GREEN}Systemd сервис создан${NC}"
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
systemctl start "$SERVICE_BOT" 2>/dev/null || true
sleep 3
BOT_STATUS=$(systemctl is-active "$SERVICE_BOT" 2>/dev/null || echo "inactive")
echo "    Статус: $BOT_STATUS"

if [ "$BOT_STATUS" != "active" ]; then
    echo ""
    echo -e "  ${RED}Бот не запустился!${NC}"
    echo "  Проверьте логи:"
    echo "    journalctl -u $SERVICE_BOT -n 30"
    echo "    tail -30 $LOG_DIR/tgbot-error.log"
fi

echo ""
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
        echo -e "  ${GREEN}Тестовое сообщение отправлено успешно!${NC}"
        echo "     Проверьте Telegram — должно прийти сообщение."
        ;;
    NO_CHATS)
        echo -e "  ${YELLOW}Нет получателей для отправки теста${NC}"
        echo "     Добавьте получателей через веб-интерфейс /settings"
        ;;
    *)
        echo -e "  ${RED}Тестовое сообщение не отправлено${NC}"
        echo ""
        echo "  Возможные причины:"
        echo "    1. Неправильный токен бота"
        echo "    2. Прокси не работает или не указан"
        echo "    3. Нет доступа к api.telegram.org"
        echo "    4. Неправильный Chat ID"
        echo ""
        echo "  Проверьте:"
        echo "    nano $CONFIG_FILE"
        echo "    tail -f $LOG_DIR/tgbot.log"
        ;;
esac

# ============================================
# ФИНАЛЬНЫЙ ВЫВОД
# ============================================
IP=$(hostname -I | awk '{print $1}')
# Определяем реальный порт из nginx конфига
WEB_PORT=$(grep -m1 'listen ' /etc/nginx/sites-available/trassir-monitor 2>/dev/null | grep -oP '\d+' | head -1)
WEB_PORT=${WEB_PORT:-8080}
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Telegram Bot v6.1 — УСТАНОВЛЕН!            ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Веб-управление:${NC}"
echo -e "   ${CYAN}http://${IP}:${WEB_PORT}/settings${NC}"
echo ""
echo -e "${BOLD}Управление ботом:${NC}"
echo -e "   Статус:      ${YELLOW}systemctl status $SERVICE_BOT${NC}"
echo -e "   Перезапуск:  ${YELLOW}systemctl restart $SERVICE_BOT${NC}"
echo -e "   Остановка:   ${YELLOW}systemctl stop $SERVICE_BOT${NC}"
echo -e "   Логи:        ${YELLOW}tail -f $LOG_DIR/tgbot.log${NC}"
echo -e "   Логи ошибок: ${YELLOW}tail -f $LOG_DIR/tgbot-error.log${NC}"
echo ""
echo -e "${BOLD}Файлы:${NC}"
echo -e "   Конфигурация: ${CYAN}$CONFIG_FILE${NC} (chmod 600)"
echo -e "   Код бота:     ${CYAN}$TGBOT_PY${NC}"
echo -e "   Бэкап:        ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "${BOLD}Формат уведомлений в Telegram:${NC}"
echo -e "   [OK]  ВОССТАНОВЛЕНИЕ — канал/сервер вернулся"
echo -e "         + время простоя (сколько был недоступен)"
echo -e "   [CAM] ОТВАЛ КАМЕР — с именами каналов"
echo -e "   [CPU] ВЫСОКАЯ НАГРУЗКА CPU"
echo -e "   [ARC] ПРОБЛЕМА С АРХИВОМ"
echo -e "   [DSK] ОШИБКА ДИСКОВ"
echo -e "   [XX]  КРИТИЧЕСКИЙ АЛЕРТ"
echo -e "   Для каждого: CPU%, камеры онлайн, архив, uptime, отклик"
echo ""
echo -e "${BOLD}Расчёт времени простоя:${NC}"
echo -e "   При восстановлении камеры — ищется момент её отвала"
echo -e "   При восстановлении сервера — ищется последний offline-алерт"
echo -e "   Пример: 'Время простоя: 2 ч 15 мин'"
echo ""
