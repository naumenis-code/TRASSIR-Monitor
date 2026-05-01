#!/bin/bash
# ============================================
# TRASSIR Monitor — Mail Notifier Installer v1.1 FIXED
# ============================================
# Автономный демон отправки алертов по Email
# Настройка SMTP через веб-интерфейс /settings
# Поддержка нескольких получателей
# Debian 11/12/13
# Русский язык
# Исправлено:
#   - Уведомления о восстановлении каналов и серверов
#   - Расчёт времени простоя
# ============================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/trassir-monitor"
SERVICE_MAIL="trassir-mailbot"
SERVICE_MAIN="trassir-monitor"
BACKUP_DIR="$INSTALL_DIR/backups/mail-$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$INSTALL_DIR/logs"
MAILBOT_PY="$INSTALL_DIR/app/mail_bot.py"
APP_PY="$INSTALL_DIR/app/app.py"
SETTINGS_HTML="$INSTALL_DIR/templates/settings.html"
VENV_PYTHON="$INSTALL_DIR/venv/bin/python3"

clear

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                              ║${NC}"
echo -e "${CYAN}║   TRASSIR Monitor — Mail Notifier v1.1       ║${NC}"
echo -e "${CYAN}║   Автономный демон Email-уведомлений         ║${NC}"
echo -e "${CYAN}║   Настройка через веб-интерфейс              ║${NC}"
echo -e "${CYAN}║   Восстановление каналов и серверов          ║${NC}"
echo -e "${CYAN}║   Debian 11/12/13 • Русский язык             ║${NC}"
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
    echo -e "   ${YELLOW}sudo bash install-mail-notifier.sh${NC}"
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

if systemctl is-active --quiet "$SERVICE_MAIL" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}⚠ Mail Notifier уже установлен и запущен.${NC}"
    echo -e "  Будет выполнена переустановка с сохранением базы данных."
    echo -e "  Сервис: ${BOLD}$SERVICE_MAIL${NC}"
    echo ""
    read -p "  Продолжить? (Enter — да, Ctrl+C — отмена): " confirm
    echo ""
    echo -e "  • Остановка старого сервиса..."
    systemctl stop "$SERVICE_MAIL" 2>/dev/null || true
    systemctl disable "$SERVICE_MAIL" 2>/dev/null || true
    echo "    ✓ Остановлен"
fi

echo ""

# ============================================
# ЗАПРОС ПАРАМЕТРОВ У ПОЛЬЗОВАТЕЛЯ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  НАЧАЛЬНАЯ НАСТРОЙКА EMAIL                   ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  Это начальные параметры SMTP-сервера."
echo -e "  Все настройки можно изменить позже через веб-интерфейс /settings"
echo ""

echo -e "  ${BOLD}1. SMTP-сервер${NC}"
echo -e "     Примеры: smtp.gmail.com, smtp.yandex.ru, mail.yourdomain.com"
echo ""
read -p "     SMTP сервер: " SMTP_SERVER

while [ -z "$SMTP_SERVER" ]; do
    echo -e "     ${RED}⚠ SMTP сервер обязателен!${NC}"
    read -p "     SMTP сервер: " SMTP_SERVER
done
echo -e "     ${GREEN}✓${NC} Сервер: $SMTP_SERVER"
echo ""

echo -e "  ${BOLD}2. SMTP порт${NC}"
echo -e "     587 — STARTTLS (рекомендуется)"
echo -e "     465 — SSL/TLS"
echo -e "     25  — без шифрования"
echo ""
read -p "     Порт (Enter для 587): " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
echo -e "     ${GREEN}✓${NC} Порт: $SMTP_PORT"
echo ""

echo -e "  ${BOLD}3. Логин для SMTP${NC}"
echo -e "     Обычно это email-адрес отправителя"
echo -e "     Пример: monitor@yourdomain.com"
echo ""
read -p "     Логин: " SMTP_USER

while [ -z "$SMTP_USER" ]; do
    echo -e "     ${RED}⚠ Логин обязателен!${NC}"
    read -p "     Логин: " SMTP_USER
done
echo -e "     ${GREEN}✓${NC} Логин: $SMTP_USER"
echo ""

echo -e "  ${BOLD}4. Пароль для SMTP${NC}"
echo -e "     Для Gmail — используйте пароль приложения (App Password)"
echo -e "     Google: Аккаунт → Безопасность → Двухэтапная → Пароли приложений"
echo ""
read -s -p "     Пароль: " SMTP_PASS
echo ""

while [ -z "$SMTP_PASS" ]; do
    echo -e "     ${RED}⚠ Пароль обязателен!${NC}"
    read -s -p "     Пароль: " SMTP_PASS
    echo ""
done
echo -e "     ${GREEN}✓${NC} Пароль: задан"
echo ""

echo -e "  ${BOLD}5. Email получателей${NC}"
echo -e "     Адреса через запятую (можно несколько)"
echo -e "     Пример: admin@company.com,duty@company.com"
echo ""
read -p "     Email получателей: " MAIL_TO

while [ -z "$MAIL_TO" ]; do
    echo -e "     ${RED}⚠ Хотя бы один получатель обязателен!${NC}"
    read -p "     Email получателей: " MAIL_TO
done

RCPT_COUNT=$(echo "$MAIL_TO" | tr ',' '\n' | grep -c '@' || true)
echo -e "     ${GREEN}✓${NC} Получателей: $RCPT_COUNT"
echo ""

echo -e "  ${BOLD}6. Интервал проверки базы данных${NC}"
echo -e "     Как часто (в секундах) демон проверяет новые алерты"
echo -e "     Рекомендуется: 15 секунд (минимум 5)"
echo ""
read -p "     Интервал (Enter для 15): " CHECK_INTERVAL
CHECK_INTERVAL=${CHECK_INTERVAL:-15}

if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [ "$CHECK_INTERVAL" -lt 5 ]; then
    echo -e "     ${YELLOW}⚠${NC} Минимум 5 секунд. Установлено: 15"
    CHECK_INTERVAL=15
fi
echo -e "     ${GREEN}✓${NC} Интервал: $CHECK_INTERVAL сек"
echo ""

echo -e "  ${BOLD}7. URL веб-интерфейса монитора${NC}"
echo -e "     Будет добавлен в письма как ссылка"
echo ""
DEFAULT_URL="http://$(hostname -I | awk '{print $1}'):8080"
read -p "     URL (Enter для $DEFAULT_URL): " MONITOR_URL
MONITOR_URL=${MONITOR_URL:-$DEFAULT_URL}
echo -e "     ${GREEN}✓${NC} URL: $MONITOR_URL"
echo ""

# ============================================
# ПОДТВЕРЖДЕНИЕ
# ============================================

echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ПАРАМЕТРЫ УСТАНОВКИ               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  📧 SMTP:       ${BOLD}${SMTP_SERVER}:${SMTP_PORT}${NC}"
echo -e "  👤 Логин:      ${BOLD}${SMTP_USER}${NC}"
echo -e "  🔑 Пароль:     ${BOLD}задан${NC}"
echo -e "  📬 Получатели: ${BOLD}${MAIL_TO}${NC}"
echo -e "  ⏱  Интервал:   ${BOLD}${CHECK_INTERVAL} сек${NC}"
echo -e "  🔗 URL:        ${BOLD}${MONITOR_URL}${NC}"
echo -e "  📁 Установка:  ${BOLD}${INSTALL_DIR}${NC}"
echo ""

read -p "Всё верно? Нажмите Enter для продолжения (Ctrl+C для отмены): " confirm
echo ""

# ============================================
# ШАГ 0: БЭКАП
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
fi

if [ -f "$SETTINGS_HTML" ]; then
    cp "$SETTINGS_HTML" "$BACKUP_DIR/settings.html.bak"
    echo -e "  ${GREEN}✓${NC} settings.html сохранён"
fi

echo ""
echo -e "${GREEN}✅ Бэкап создан${NC}"
echo ""

# ============================================
# ШАГ 1: ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [1/7] ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ            ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

source "$INSTALL_DIR/venv/bin/activate"

export MAIL_TO_ENV="$MAIL_TO"
export SMTP_SERVER_ENV="$SMTP_SERVER"
export SMTP_PORT_ENV="$SMTP_PORT"
export SMTP_USER_ENV="$SMTP_USER"
export SMTP_PASS_ENV="$SMTP_PASS"
export MONITOR_URL_ENV="$MONITOR_URL"

$VENV_PYTHON << 'PYEOF'
import sqlite3, os

DB_PATH = '/opt/trassir-monitor/data/trassir.db'

print("  • Подключение к базе данных...")
conn = sqlite3.connect(DB_PATH)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA busy_timeout=5000")
conn.row_factory = sqlite3.Row
print("    ✓ Подключено")

print("")
print("  • Создание таблиц Email:")

conn.execute("""
    CREATE TABLE IF NOT EXISTS mail_recipients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        name TEXT DEFAULT '',
        enabled BOOLEAN DEFAULT 1,
        warning BOOLEAN DEFAULT 1,
        critical BOOLEAN DEFAULT 1,
        info BOOLEAN DEFAULT 0,
        added_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
""")
print("    ✓ mail_recipients (получатели)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS mail_settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )
""")
print("    ✓ mail_settings (настройки SMTP)")

conn.execute("""
    CREATE TABLE IF NOT EXISTS mail_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts DATETIME,
        alert_key TEXT,
        email TEXT,
        subject TEXT
    )
""")
print("    ✓ mail_logs (история отправок)")

conn.execute("CREATE INDEX IF NOT EXISTS idx_mail_logs_key ON mail_logs(alert_key, ts)")
conn.execute("CREATE INDEX IF NOT EXISTS idx_mail_rcpt_enabled ON mail_recipients(enabled)")
print("    ✓ Индексы созданы")

# Настройки по умолчанию из переменных среды
defaults = {
    'enabled': '1',
    'smtp_server': os.environ.get('SMTP_SERVER_ENV', ''),
    'smtp_port': os.environ.get('SMTP_PORT_ENV', '587'),
    'smtp_user': os.environ.get('SMTP_USER_ENV', ''),
    'smtp_pass': os.environ.get('SMTP_PASS_ENV', ''),
    'from_name': 'TRASSIR Monitor',
    'from_addr': os.environ.get('SMTP_USER_ENV', ''),
    'monitor_url': os.environ.get('MONITOR_URL_ENV', ''),
    'notify_interval': '0',
}
for k, v in defaults.items():
    conn.execute("INSERT OR IGNORE INTO mail_settings (key, value) VALUES (?, ?)", (k, v))
print("    ✓ Настройки SMTP сохранены")

print("")
print("  • Добавление получателей:")

mail_list = os.environ.get('MAIL_TO_ENV', '').split(',')
for addr in mail_list:
    addr = addr.strip()
    if '@' in addr:
        try:
            conn.execute("INSERT OR IGNORE INTO mail_recipients (email) VALUES (?)", (addr,))
            print(f"    ✓ {addr} добавлен")
        except Exception as e:
            print(f"    ⚠ Ошибка: {e}")

total = conn.execute("SELECT COUNT(*) FROM mail_recipients").fetchone()[0]
print(f"    Всего получателей: {total}")

conn.commit()
conn.close()
print("")
print("  ✅ База данных готова")
PYEOF

deactivate

echo ""
echo -e "${GREEN}✅ База данных инициализирована${NC}"
echo ""

# ============================================
# ШАГ 2: СОЗДАНИЕ ДЕМОНА mail_bot.py (ИСПРАВЛЕННАЯ ВЕРСИЯ)
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [2/7] СОЗДАНИЕ ДЕМОНА ПОЧТЫ                ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Генерация mail_bot.py..."

cat > "$MAILBOT_PY" << 'MAILBOTEOF'
#!/usr/bin/env python3
"""
TRASSIR Monitor — Mail Bot Daemon v1.1 FIXED
Автономный демон Email-уведомлений

Принцип работы:
1. Проверяет таблицу alerts каждые N секунд
2. Находит новые алерты (включая восстановления)
3. Вычисляет время простоя для восстановлений
4. Формирует красивое HTML-письмо на русском языке
5. Отправляет всем активным получателям
6. Помечает алерт как отправленный

Исправления v1.1:
- Добавлены уведомления о восстановлении (аналог telegram-бота)
- Добавлен расчёт времени простоя
"""

import os
import re
import sys
import time
import sqlite3
import smtplib
import traceback
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

# ============================================
# КОНФИГУРАЦИЯ
# ============================================

BASE_DIR = "/opt/trassir-monitor"
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
CHECK_INTERVAL = 15

# ============================================
# РАБОТА С БАЗОЙ ДАННЫХ
# ============================================

def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.row_factory = sqlite3.Row
    return conn


def get_mail_settings():
    """Читает настройки SMTP из БД"""
    try:
        conn = get_db()
        rows = conn.execute("SELECT key, value FROM mail_settings").fetchall()
        conn.close()
        return dict(rows)
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка чтения настроек: {e}")
        return {}


def is_mail_enabled():
    """Проверяет, включены ли уведомления"""
    try:
        conn = get_db()
        row = conn.execute(
            "SELECT value FROM mail_settings WHERE key = 'enabled'"
        ).fetchone()
        conn.close()
        return row is not None and row[0] == '1'
    except Exception:
        return False


def get_enabled_recipients():
    """Получает список активных получателей"""
    try:
        conn = get_db()
        rows = conn.execute(
            "SELECT * FROM mail_recipients WHERE enabled = 1"
        ).fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка получения получателей: {e}")
        return []


def get_new_alerts():
    """
    Получает список новых алертов (ещё не отправленных по email).
    Включает восстановления каналов и серверов.
    """
    conn = get_db()
    try:
        # Обычные алерты (warning, critical)
        alerts_rows = conn.execute(
            """SELECT
                   a.id, a.server_id, a.level, a.msg, a.ts, a.ack,
                   s.name as server_name, s.ip as server_ip
               FROM alerts a
               JOIN servers s ON a.server_id = s.id
               WHERE a.ack = 0
                 AND a.level IN ('warning', 'critical')
                 AND NOT EXISTS (
                     SELECT 1 FROM mail_logs ml
                     WHERE ml.alert_key = CAST(a.id AS TEXT)
                 )
               ORDER BY a.ts ASC"""
        ).fetchall()

        # Восстановления (info + ключевые слова)
        recovery_rows = conn.execute(
            """SELECT
                   a.id, a.server_id, a.level, a.msg, a.ts, a.ack,
                   s.name as server_name, s.ip as server_ip
               FROM alerts a
               JOIN servers s ON a.server_id = s.id
               WHERE a.level = 'info'
                 AND (
                       a.msg LIKE '%восстановлен%'
                    OR a.msg LIKE '%restored%'
                    OR a.msg LIKE '%back online%'
                    OR a.msg LIKE '%вернулся%'
                 )
                 AND NOT EXISTS (
                     SELECT 1 FROM mail_logs ml
                     WHERE ml.alert_key = CAST(a.id AS TEXT)
                 )
               ORDER BY a.ts ASC"""
        ).fetchall()

        result = []
        for row in list(alerts_rows) + list(recovery_rows):
            d = dict(row)
            # Получаем health
            health_row = conn.execute(
                """SELECT cpu, disks, ch_total, ch_online, arch, uptime, rt
                   FROM health
                   WHERE server_id = ?
                   ORDER BY ts DESC LIMIT 1""",
                (d['server_id'],)
            ).fetchone()
            d['health'] = dict(health_row) if health_row else {
                'cpu': '?', 'ch_online': '?', 'ch_total': '?',
                'arch': '?', 'uptime': 0, 'rt': '?'
            }
            # Для восстановлений считаем время простоя
            if d['level'] == 'info' or 'восстановлен' in d['msg'].lower():
                d['downtime'] = calc_downtime_for_alert(conn, d)
            else:
                d['downtime'] = ''
            result.append(d)

        return result
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка получения алертов: {e}")
        traceback.print_exc()
        return []
    finally:
        conn.close()


def calc_downtime_for_alert(conn, alert):
    """
    Вычисляет время простоя для алерта о восстановлении.
    Логика полностью повторяет telegram-бота.
    """
    msg = alert['msg']
    server_id = alert['server_id']
    recovery_ts_str = alert['ts']

    try:
        recovery_dt = datetime.strptime(recovery_ts_str, '%Y-%m-%d %H:%M:%S')
    except Exception:
        return ''

    # Попытка 1: восстановление канала (камеры)
    channel_match = re.search(r'#\d+\s+[^\,\]\n]+', msg)
    if channel_match:
        channel_name = channel_match.group(0).strip()
        try:
            offline_row = conn.execute(
                """SELECT ts FROM alerts
                   WHERE server_id = ?
                     AND (msg LIKE '%' || ? || '%' OR msg LIKE 'Камер офлайн%')
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

    # Попытка 2: восстановление сервера
    msg_lower = msg.lower()
    if 'сервер' in msg_lower or 'server' in msg_lower:
        try:
            offline_row = conn.execute(
                """SELECT ts FROM alerts
                   WHERE server_id = ?
                     AND (msg LIKE '%недоступ%' OR msg LIKE '%offline%'
                          OR msg LIKE '%не отвечает%' OR msg LIKE '%потеря связи%'
                          OR level = 'critical')
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

    # Попытка 3: по таблице health
    try:
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


def mark_alert_as_sent(alert_id, email, subject):
    """Помечает алерт как отправленный"""
    conn = get_db()
    try:
        conn.execute(
            """INSERT OR IGNORE INTO mail_logs (ts, alert_key, email, subject)
               VALUES (datetime('now', '+3 hours'), ?, ?, ?)""",
            (str(alert_id), str(email), str(subject))
        )
        conn.commit()
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка маркировки: {e}")
    finally:
        conn.close()


def cleanup_old_logs():
    """Удаляет старые записи из mail_logs (старше 7 дней)"""
    try:
        conn = get_db()
        deleted = conn.execute(
            "DELETE FROM mail_logs WHERE ts < datetime('now', '+3 hours', '-7 days')"
        ).rowcount
        conn.commit()
        conn.close()
        if deleted > 0:
            print(f"[{datetime.now()}] 🧹 Очищено старых записей: {deleted}")
    except Exception as e:
        print(f"[{datetime.now()}] ⚠ Ошибка очистки: {e}")


# ============================================
# ФОРМАТИРОВАНИЕ
# ============================================

def format_uptime(seconds):
    """Форматирует uptime из секунд"""
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


def get_alert_style(alert_data):
    """Определяет стиль и заголовок алерта"""
    level = alert_data.get('level', 'warning')
    message = alert_data.get('msg', '').lower()

    # Восстановления
    if 'восстановлен' in message or 'restored' in message or 'back online' in message:
        if 'канал' in message or 'channel' in message or 'камер' in message:
            return {
                'emoji': '✅', 'color': '#10b981', 'bg': '#064e3b',
                'subject_prefix': 'ВОССТАНОВЛЕНИЕ КАМЕР', 'header': 'ВОССТАНОВЛЕНИЕ КАМЕР'
            }
        if 'сервер' in message or 'server' in message:
            return {
                'emoji': '✅', 'color': '#10b981', 'bg': '#064e3b',
                'subject_prefix': 'СЕРВЕР ВОССТАНОВЛЕН', 'header': 'СЕРВЕР ВОССТАНОВЛЕН'
            }
        return {
            'emoji': '✅', 'color': '#10b981', 'bg': '#064e3b',
            'subject_prefix': 'ВОССТАНОВЛЕНИЕ', 'header': 'ВОССТАНОВЛЕНИЕ'
        }

    if level == 'critical':
        return {
            'emoji': '🔴', 'color': '#ef4444', 'bg': '#7f1d1d',
            'subject_prefix': 'КРИТИЧЕСКИЙ АЛЕРТ', 'header': 'КРИТИЧЕСКИЙ АЛЕРТ'
        }
    if 'камер' in message or 'camera' in message or 'канал' in message or 'channel' in message:
        return {
            'emoji': '📷', 'color': '#f59e0b', 'bg': '#78350f',
            'subject_prefix': 'ОТВАЛ КАМЕР', 'header': 'ОТВАЛ КАМЕР'
        }
    if 'cpu' in message or 'процессор' in message:
        return {
            'emoji': '🔥', 'color': '#f97316', 'bg': '#7c2d12',
            'subject_prefix': 'ВЫСОКАЯ НАГРУЗКА CPU', 'header': 'ВЫСОКАЯ НАГРУЗКА CPU'
        }
    if 'архив' in message or 'archive' in message:
        return {
            'emoji': '💾', 'color': '#8b5cf6', 'bg': '#4c1d95',
            'subject_prefix': 'ПРОБЛЕМА С АРХИВОМ', 'header': 'ПРОБЛЕМА С АРХИВОМ'
        }
    if 'диск' in message or 'disk' in message:
        return {
            'emoji': '💿', 'color': '#ef4444', 'bg': '#7f1d1d',
            'subject_prefix': 'ОШИБКА ДИСКОВ', 'header': 'ОШИБКА ДИСКОВ'
        }
    return {
        'emoji': '⚠️', 'color': '#f59e0b', 'bg': '#78350f',
        'subject_prefix': 'ПРЕДУПРЕЖДЕНИЕ', 'header': 'ПРЕДУПРЕЖДЕНИЕ'
    }


def format_alert_email(alert_data, settings):
    """Формирует HTML-письмо для алерта"""
    style = get_alert_style(alert_data)
    server_name = alert_data.get('server_name', 'Неизвестный сервер')
    server_ip = alert_data.get('server_ip', '')
    server_id = alert_data.get('server_id', '')
    message = alert_data.get('msg', 'Нет описания')
    timestamp = alert_data.get('ts', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    health = alert_data.get('health', {})
    monitor_url = settings.get('monitor_url', '')
    downtime = alert_data.get('downtime', '')

    cpu_val = health.get('cpu', '?')
    cpu_str = f"{cpu_val:.1f}%" if isinstance(cpu_val, (int, float)) else f"{cpu_val}%"
    arch_val = health.get('arch', '?')
    arch_str = f"{arch_val:.1f} дн" if isinstance(arch_val, (int, float)) else f"{arch_val} дн"

    # Добавление информации о времени простоя
    downtime_html = ""
    if downtime:
        downtime_html = f"""
              <!-- Время простоя -->
              <tr>
                <td style="padding:12px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">⏱ Время простоя</td>
                      <td style="color:#f0f6fc;font-size:15px;font-weight:bold;">{downtime}</td>
                    </tr>
                  </table>
                </td>
              </tr>"""

    server_link = ""
    if monitor_url and server_id:
        server_link = f"""
              <tr>
                <td colspan="2" style="padding: 16px 0 0 0; text-align: center;">
                  <a href="{monitor_url}/server/{server_id}"
                     style="display: inline-block; background-color: {style['color']};
                            color: #ffffff; padding: 10px 24px; border-radius: 6px;
                            text-decoration: none; font-weight: bold;">
                    🔗 Открыть в TRASSIR Monitor
                  </a>
                </td>
              </tr>"""

    subject = f"{style['subject_prefix']} — {server_name}"

    html = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background-color:#0d1117;font-family:Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0"
       style="background-color:#0d1117;padding:32px 16px;">
  <tr>
    <td align="center">
      <table width="600" cellpadding="0" cellspacing="0"
             style="background-color:#161b22;border-radius:12px;
                    border:1px solid #30363d;overflow:hidden;">

        <!-- Заголовок -->
        <tr>
          <td style="background-color:{style['bg']};padding:24px 28px;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td>
                  <div style="font-size:22px;font-weight:bold;color:#ffffff;">
                    {style['emoji']} {style['header']}
                  </div>
                  <div style="font-size:14px;color:rgba(255,255,255,0.75);margin-top:4px;">
                    TRASSIR Monitor System
                  </div>
                </td>
                <td align="right">
                  <div style="background:rgba(0,0,0,0.3);border-radius:8px;
                              padding:8px 14px;color:#ffffff;font-size:13px;">
                    {timestamp}
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Основная информация -->
        <tr>
          <td style="padding:24px 28px;">
            <table width="100%" cellpadding="0" cellspacing="0">

              <!-- Сервер -->
              <tr>
                <td style="padding:10px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">🖥 Сервер</td>
                      <td style="color:#f0f6fc;font-size:15px;font-weight:bold;">
                          {server_name}</td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- IP -->
              <tr>
                <td style="padding:10px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">📍 IP адрес</td>
                      <td style="color:#f0f6fc;font-size:14px;">{server_ip}</td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- Событие -->
              <tr>
                <td style="padding:12px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;
                                 vertical-align:top;padding-top:2px;">⚠ Событие</td>
                      <td>
                        <div style="background-color:{style['bg']};border-left:3px solid {style['color']};
                                    border-radius:4px;padding:10px 14px;
                                    color:#f0f6fc;font-size:14px;">
                          {message}
                        </div>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              {downtime_html}

              <!-- Состояние сервера -->
              <tr>
                <td style="padding:16px 0 8px 0;">
                  <div style="color:#8b949e;font-size:12px;
                              text-transform:uppercase;letter-spacing:1px;
                              margin-bottom:12px;">
                    📊 Текущее состояние сервера
                  </div>
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">Загрузка CPU</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">{cpu_str}</span>
                      </td>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">Камеры онлайн</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">
                          {health.get('ch_online', '?')} / {health.get('ch_total', '?')}
                        </span>
                      </td>
                    </tr>
                    <tr>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">Глубина архива</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">{arch_str}</span>
                      </td>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">Uptime</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">
                          {format_uptime(health.get('uptime', 0))}
                        </span>
                      </td>
                    </tr>
                    <tr>
                      <td colspan="2" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">Время отклика</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">
                          {health.get('rt', '?')} мс
                        </span>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              {server_link}

            </table>
          </td>
        </tr>

        <!-- Подвал -->
        <tr>
          <td style="background-color:#0d1117;padding:16px 28px;
                     border-top:1px solid #21262d;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="color:#484f58;font-size:12px;">
                  TRASSIR Monitor • Автоматическое уведомление
                </td>
                <td align="right" style="color:#484f58;font-size:12px;">
                  Не отвечайте на это письмо
                </td>
              </tr>
            </table>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>"""

    return subject, html


def format_test_email(settings):
    """Формирует тестовое HTML-письмо"""
    monitor_url = settings.get('monitor_url', 'не указан')
    ts = datetime.now().strftime("%d.%m.%Y %H:%M:%S")

    subject = "✅ TRASSIR Monitor — Email уведомления настроены"
    html = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background-color:#0d1117;font-family:Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0"
       style="background-color:#0d1117;padding:32px 16px;">
  <tr>
    <td align="center">
      <table width="600" cellpadding="0" cellspacing="0"
             style="background-color:#161b22;border-radius:12px;
                    border:1px solid #30363d;overflow:hidden;">
        <tr>
          <td style="background-color:#064e3b;padding:24px 28px;">
            <div style="font-size:22px;font-weight:bold;color:#ffffff;">
              ✅ Email уведомления работают!
            </div>
            <div style="font-size:14px;color:rgba(255,255,255,0.75);margin-top:4px;">
              TRASSIR Monitor — тестовое сообщение
            </div>
          </td>
        </tr>
        <tr>
          <td style="padding:24px 28px;color:#f0f6fc;">
            <p style="margin:0 0 12px 0;">✅ SMTP-сервер подключён успешно</p>
            <p style="margin:0 0 12px 0;">📡 Email-уведомления успешно настроены</p>
            <p style="margin:0 0 12px 0;">🔗 Веб-интерфейс: {monitor_url}</p>
            <p style="margin:0 0 0 0;color:#8b949e;font-size:13px;">⏰ {ts} МСК</p>
          </td>
        </tr>
        <tr>
          <td style="background-color:#0d1117;padding:12px 28px;
                     border-top:1px solid #21262d;">
            <span style="color:#484f58;font-size:12px;">
              TRASSIR Monitor • Автоматическое уведомление
            </span>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>"""
    return subject, html


# ============================================
# ОТПРАВКА EMAIL
# ============================================

def send_email(to_addr, to_name, subject, html_body, settings):
    """Отправляет HTML-письмо через SMTP"""
    smtp_server = settings.get('smtp_server', '')
    smtp_port = int(settings.get('smtp_port', 587))
    smtp_user = settings.get('smtp_user', '')
    smtp_pass = settings.get('smtp_pass', '')
    from_addr = settings.get('from_addr', smtp_user)
    from_name = settings.get('from_name', 'TRASSIR Monitor')

    if not smtp_server or not smtp_user or not smtp_pass:
        print(f"[{datetime.now()}] ❌ SMTP не настроен (server/user/pass обязательны)")
        return False

    try:
        msg = MIMEMultipart('alternative')
        msg['From'] = f"{from_name} <{from_addr}>"
        msg['To'] = f"{to_name} <{to_addr}>" if to_name else to_addr
        msg['Subject'] = subject
        msg['X-Mailer'] = 'TRASSIR Monitor v1.1'

        msg.attach(MIMEText(html_body, 'html', 'utf-8'))

        if smtp_port == 465:
            import ssl
            ctx = ssl.create_default_context()
            with smtplib.SMTP_SSL(smtp_server, smtp_port, context=ctx, timeout=20) as server:
                server.login(smtp_user, smtp_pass)
                server.send_message(msg)
        else:
            with smtplib.SMTP(smtp_server, smtp_port, timeout=20) as server:
                server.ehlo()
                server.starttls()
                server.ehlo()
                server.login(smtp_user, smtp_pass)
                server.send_message(msg)

        return True

    except smtplib.SMTPAuthenticationError:
        print(f"[{datetime.now()}] ❌ Ошибка аутентификации SMTP: неверный логин/пароль")
        return False
    except smtplib.SMTPConnectError:
        print(f"[{datetime.now()}] ❌ Не удалось подключиться к {smtp_server}:{smtp_port}")
        return False
    except Exception as e:
        print(f"[{datetime.now()}] ❌ Ошибка отправки на {to_addr}: {e}")
        return False


# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================

def run_bot():
    """Основной бесконечный цикл работы демона"""
    print(f"[{datetime.now()}] 📧 Mail Bot v1.1 запускается...")
    print(f"[{datetime.now()}] 📁 База данных: {DB_PATH}")
    print(f"[{datetime.now()}] ⏱  Интервал проверки: {CHECK_INTERVAL} сек")

    settings = get_mail_settings()
    if settings.get('smtp_server'):
        print(f"[{datetime.now()}] 📮 SMTP: {settings['smtp_server']}:{settings.get('smtp_port', 587)}")
    else:
        print(f"[{datetime.now()}] ⚠ SMTP не настроен — настройте через /settings")

    cleanup_old_logs()

    total_sent = 0
    checks = 0

    while True:
        try:
            checks += 1

            if not is_mail_enabled():
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⏸ Email уведомления отключены в настройках")
                time.sleep(CHECK_INTERVAL)
                continue

            settings = get_mail_settings()

            if not settings.get('smtp_server') or not settings.get('smtp_user'):
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⚠ SMTP не настроен")
                time.sleep(CHECK_INTERVAL)
                continue

            recipients = get_enabled_recipients()
            if not recipients:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] ⚠ Нет активных получателей")
                time.sleep(CHECK_INTERVAL)
                continue

            alerts = get_new_alerts()

            for alert in alerts:
                subject, html_body = format_alert_email(alert, settings)
                sent_to = []

                for rcpt in recipients:
                    email = rcpt['email']

                    if alert['level'] == 'critical' and not rcpt.get('critical', True):
                        continue
                    if alert['level'] == 'warning' and not rcpt.get('warning', True):
                        continue
                    if alert['level'] == 'info' and not rcpt.get('info', False):
                        continue

                    if send_email(email, rcpt.get('name', ''), subject, html_body, settings):
                        mark_alert_as_sent(alert['id'], email, subject)
                        sent_to.append(email)
                        total_sent += 1
                        time.sleep(0.2)

                if sent_to:
                    downtime_info = f" | простой: {alert['downtime']}" if alert.get('downtime') else ""
                    print(f"[{datetime.now()}] ✅ Отправлено: {alert['msg'][:60]}{downtime_info}")
                    print(f"[{datetime.now()}]    Получатели: {', '.join(sent_to)}")

            if checks % 360 == 0:
                cleanup_old_logs()

        except KeyboardInterrupt:
            print(f"\n[{datetime.now()}] 🛑 Mail Bot остановлен. Отправлено: {total_sent}")
            break
        except Exception as e:
            print(f"[{datetime.now()}] ❌ Ошибка: {e}")
            traceback.print_exc()

        time.sleep(CHECK_INTERVAL)


if __name__ == '__main__':
    run_bot()
MAILBOTEOF

sed -i "s/CHECK_INTERVAL = 15/CHECK_INTERVAL = $CHECK_INTERVAL/" "$MAILBOT_PY"

chmod +x "$MAILBOT_PY"
chown www-data:www-data "$MAILBOT_PY" 2>/dev/null || true

source "$INSTALL_DIR/venv/bin/activate"
$VENV_PYTHON -c "import ast; ast.parse(open('$MAILBOT_PY').read()); print('  ✓ Синтаксис mail_bot.py корректен')"
deactivate

echo "  • Файл создан: $MAILBOT_PY"
echo "    Размер: $(wc -c < "$MAILBOT_PY") байт"
echo "    Строк: $(wc -l < "$MAILBOT_PY")"
echo ""
echo -e "${GREEN}✅ Демон почты создан${NC}"
echo ""

# ============================================
# ШАГ 3: ДОБАВЛЕНИЕ API В APP.PY
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [3/7] ИНТЕГРАЦИЯ API В APP.PY               ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if grep -q 'def api_mail_recipients\|MAIL NOTIFIER API' "$APP_PY" 2>/dev/null; then
    echo "  ⚠ API для Email уже существует в app.py"
    echo "    Пропускаем интеграцию."
else
    echo "  • Добавление API endpoints в app.py..."

    source "$INSTALL_DIR/venv/bin/activate"
    $VENV_PYTHON << 'PYAPIEOF'
app_path = "/opt/trassir-monitor/app/app.py"

with open(app_path, 'r') as f:
    content = f.read()

api_block = '''

# ============================================
# MAIL NOTIFIER API — УПРАВЛЕНИЕ EMAIL УВЕДОМЛЕНИЯМИ
# ============================================

@app.route("/api/mail/recipients", methods=["GET", "POST", "PUT", "DELETE"])
def api_mail_recipients():
    """API для управления получателями Email уведомлений"""
    conn = get_db()
    if request.method == "GET":
        rows = conn.execute("SELECT * FROM mail_recipients ORDER BY id").fetchall()
        conn.close()
        return jsonify([dict(r) for r in rows])
    elif request.method == "POST":
        data = request.json
        email = data.get("email", "").strip()
        name = data.get("name", "").strip()
        if not email or "@" not in email:
            conn.close()
            return jsonify({"ok": 0, "error": "Некорректный email адрес"}), 400
        try:
            conn.execute("INSERT INTO mail_recipients (email, name) VALUES (?, ?)", (email, name))
            conn.commit()
            conn.close()
            return jsonify({"ok": 1, "message": "Получатель добавлен"})
        except:
            conn.close()
            return jsonify({"ok": 0, "error": "Такой email уже существует"}), 400
    elif request.method == "PUT":
        data = request.json
        rid = data.get("id")
        if rid:
            conn.execute(
                "UPDATE mail_recipients SET name=?, enabled=?, warning=?, critical=?, info=? WHERE id=?",
                (data.get("name", ""), data.get("enabled", 1), data.get("warning", 1),
                 data.get("critical", 1), data.get("info", 0), rid)
            )
            conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки получателя обновлены"})
    elif request.method == "DELETE":
        rid = request.args.get("id")
        if rid:
            conn.execute("DELETE FROM mail_recipients WHERE id=?", (rid,))
            conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Получатель удалён"})


@app.route("/api/mail/settings", methods=["GET", "POST"])
def api_mail_settings():
    """API для управления SMTP настройками"""
    conn = get_db()
    if request.method == "GET":
        rows = conn.execute("SELECT key, value FROM mail_settings").fetchall()
        settings = dict(rows)
        # Маскируем пароль для отображения
        if settings.get("smtp_pass"):
            settings["smtp_pass_masked"] = "•" * 8
            settings["smtp_configured"] = True
        else:
            settings["smtp_configured"] = False
        settings.pop("smtp_pass", None)
        conn.close()
        return jsonify(settings)
    elif request.method == "POST":
        data = request.json
        for key, value in data.items():
            conn.execute(
                "INSERT OR REPLACE INTO mail_settings (key, value) VALUES (?, ?)",
                (key, str(value))
            )
        conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки сохранены"})


@app.route("/api/mail/test", methods=["POST"])
def api_mail_test():
    """API для отправки тестового письма"""
    import sys, os
    sys.path.insert(0, "/opt/trassir-monitor")
    from app.mail_bot import (
        get_mail_settings, get_enabled_recipients,
        format_test_email, send_email
    )
    data = request.json or {}
    to_addr = data.get("email")

    settings = get_mail_settings()
    if not settings.get("smtp_server"):
        return jsonify({"ok": 0, "error": "SMTP сервер не настроен"}), 400

    if not to_addr:
        recipients = get_enabled_recipients()
        if not recipients:
            return jsonify({"ok": 0, "error": "Нет активных получателей"}), 400
        to_addr = recipients[0]["email"]

    subject, html_body = format_test_email(settings)
    ok = send_email(to_addr, "", subject, html_body, settings)
    if ok:
        return jsonify({"ok": 1, "message": f"Тестовое письмо отправлено на {to_addr}"})
    return jsonify({"ok": 0, "error": "Ошибка отправки. Проверьте SMTP настройки."})
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

    if $VENV_PYTHON -c "import ast; ast.parse(open('$APP_PY').read())" 2>&1; then
        echo "    ✓ Синтаксис app.py корректен"
    else
        echo "    ❌ Синтаксическая ошибка! Восстанавливаю бэкап..."
        cp "$BACKUP_DIR/app.py.bak" "$APP_PY"
        echo "    ✓ Восстановлено"
    fi
    deactivate
fi

echo ""
echo -e "${GREEN}✅ Интеграция API завершена${NC}"
echo ""

# ============================================
# ШАГ 4: ОБНОВЛЕНИЕ settings.html
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [4/7] ОБНОВЛЕНИЕ ВЕБ-ИНТЕРФЕЙСА            ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

if grep -q 'mailLoadSettings\|mail_recipients\|MAIL NOTIFIER' "$SETTINGS_HTML" 2>/dev/null; then
    echo "  ⚠ Карточка Email уже существует в settings.html"
    echo "    Пропускаем обновление."
else
    echo "  • Добавление карточки Email в settings.html..."

    python3 << 'PYHTML'
import re

path = "/opt/trassir-monitor/templates/settings.html"

with open(path, 'r') as f:
    content = f.read()

mail_card = '''

    <!-- ============================================ -->
    <!-- EMAIL УВЕДОМЛЕНИЯ                            -->
    <!-- ============================================ -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header d-flex justify-content-between align-items-center">
                <span><i class="bi bi-envelope"></i> Email уведомления</span>
                <span class="badge fs-6" id="mailStatusBadge">Загрузка...</span>
            </div>
            <div class="card-body">
                <style>
                    .mail-form-control {
                        color: #fff !important;
                        background: #1a1d27 !important;
                        border-color: #2d3239 !important;
                    }
                    .mail-form-control::placeholder { color: #6b7280 !important; }
                </style>

                <!-- SMTP настройки -->
                <div id="mailSmtpInfo" class="mb-3 p-3 rounded" style="background: var(--bg);">
                    <div class="spinner-border spinner-border-sm" role="status"></div>
                    Загрузка SMTP конфигурации...
                </div>

                <div class="mb-2">
                    <a href="#mailSmtpForm" data-bs-toggle="collapse"
                       class="btn btn-outline-secondary btn-sm w-100">
                        <i class="bi bi-gear"></i> Настроить SMTP сервер
                    </a>
                </div>

                <div class="collapse mb-3" id="mailSmtpForm">
                    <div class="p-3 rounded" style="background: var(--bg); border: 1px solid #2d3239;">
                        <div class="row g-2">
                            <div class="col-8">
                                <label class="form-label small">SMTP сервер</label>
                                <input type="text" class="form-control form-control-sm mail-form-control"
                                       id="mailSmtpServer" placeholder="smtp.gmail.com">
                            </div>
                            <div class="col-4">
                                <label class="form-label small">Порт</label>
                                <input type="number" class="form-control form-control-sm mail-form-control"
                                       id="mailSmtpPort" placeholder="587">
                            </div>
                            <div class="col-6">
                                <label class="form-label small">Логин</label>
                                <input type="text" class="form-control form-control-sm mail-form-control"
                                       id="mailSmtpUser" placeholder="user@domain.com">
                            </div>
                            <div class="col-6">
                                <label class="form-label small">Пароль</label>
                                <input type="password" class="form-control form-control-sm mail-form-control"
                                       id="mailSmtpPass" placeholder="••••••••">
                            </div>
                            <div class="col-6">
                                <label class="form-label small">Имя отправителя</label>
                                <input type="text" class="form-control form-control-sm mail-form-control"
                                       id="mailFromName" placeholder="TRASSIR Monitor">
                            </div>
                            <div class="col-6">
                                <label class="form-label small">Email отправителя</label>
                                <input type="text" class="form-control form-control-sm mail-form-control"
                                       id="mailFromAddr" placeholder="monitor@domain.com">
                            </div>
                            <div class="col-12">
                                <label class="form-label small">URL монитора (для ссылок в письмах)</label>
                                <input type="text" class="form-control form-control-sm mail-form-control"
                                       id="mailMonitorUrl" placeholder="http://192.168.1.100:8080">
                            </div>
                            <div class="col-12">
                                <button class="btn btn-primary btn-sm w-100" onclick="mailSaveSmtp()">
                                    <i class="bi bi-check-lg"></i> Сохранить SMTP
                                </button>
                            </div>
                        </div>
                        <small class="text-muted d-block mt-2">
                            Gmail: используйте пароль приложения (App Password)
                        </small>
                    </div>
                </div>

                <!-- Получатели -->
                <div class="mb-3">
                    <label class="form-label">📬 Получатели уведомлений:</label>
                    <div id="mailRcptList" class="mb-3" style="max-height: 200px; overflow-y: auto;">
                        <div class="text-center py-3">
                            <div class="spinner-border spinner-border-sm" role="status"></div>
                            <span class="ms-2" style="color: var(--muted);">Загрузка...</span>
                        </div>
                    </div>
                    <div class="input-group input-group-sm mb-2">
                        <input type="email" class="form-control mail-form-control"
                               id="mailNewEmail" placeholder="email@domain.com">
                        <input type="text" class="form-control mail-form-control"
                               id="mailNewName" placeholder="Имя">
                        <button class="btn btn-primary" onclick="mailAddRecipient()">
                            <i class="bi bi-plus-lg"></i>
                        </button>
                    </div>
                </div>

                <!-- Включить/выключить -->
                <div class="form-check form-switch mb-3">
                    <input class="form-check-input" type="checkbox"
                           id="mailEnabled" onchange="mailSaveEnabled()">
                    <label class="form-check-label">
                        <b>Включить Email уведомления</b>
                    </label>
                </div>

                <!-- Кнопки -->
                <div class="d-flex gap-2">
                    <button class="btn btn-outline-info btn-sm" onclick="mailTest()">
                        <i class="bi bi-send"></i> Тест
                    </button>
                    <button class="btn btn-outline-secondary btn-sm" onclick="mailRefresh()">
                        <i class="bi bi-arrow-clockwise"></i> Обновить
                    </button>
                </div>
                <div id="mailResult" class="mt-2" style="display: none;"></div>
            </div>
        </div>
    </div>

<script>
function mailRefresh(){ mailLoadSettings(); mailLoadRecipients(); }

function mailLoadSettings(){
    fetch("/api/mail/settings").then(function(r){return r.json()}).then(function(s){
        document.getElementById("mailEnabled").checked = (s.enabled === "1");

        var b = document.getElementById("mailStatusBadge");
        if(s.enabled === "1" && s.smtp_configured){
            b.className = "badge bg-success fs-6"; b.textContent = "✅ Активен";
        } else if(s.enabled === "1"){
            b.className = "badge bg-warning fs-6"; b.textContent = "⚠ Нет SMTP";
        } else {
            b.className = "badge bg-secondary fs-6"; b.textContent = "⏸ Выключен";
        }

        var info = "";
        if(s.smtp_configured){
            info = "<b>SMTP:</b> <span style='color:var(--green)'>" +
                   (s.smtp_server || "?") + ":" + (s.smtp_port || "587") + "</span>";
            if(s.smtp_user) info += " | <b>Логин:</b> " + s.smtp_user;
            if(s.monitor_url) info += "<br><b>URL:</b> " + s.monitor_url;
        } else {
            info = "<span style='color:var(--red)'>❌ SMTP не настроен</span>";
        }
        document.getElementById("mailSmtpInfo").innerHTML = info;

        // Заполняем форму
        if(s.smtp_server) document.getElementById("mailSmtpServer").value = s.smtp_server;
        if(s.smtp_port)   document.getElementById("mailSmtpPort").value = s.smtp_port;
        if(s.smtp_user)   document.getElementById("mailSmtpUser").value = s.smtp_user;
        if(s.from_name)   document.getElementById("mailFromName").value = s.from_name;
        if(s.from_addr)   document.getElementById("mailFromAddr").value = s.from_addr;
        if(s.monitor_url) document.getElementById("mailMonitorUrl").value = s.monitor_url;
    });
}

function mailLoadRecipients(){
    fetch("/api/mail/recipients").then(function(r){return r.json()}).then(function(list){
        var h = "";
        if(list.length === 0){
            h = "<p style='color:var(--muted)'>Нет получателей</p>";
        } else {
            list.forEach(function(r){
                h += "<div style='display:flex;justify-content:space-between;align-items:center;" +
                     "margin-bottom:4px;padding:6px 10px;background:var(--bg);border-radius:6px'>";
                h += "<div><span class='badge bg-" + (r.enabled ? "success" : "secondary") +
                     " me-1'>" + (r.enabled ? "вкл" : "выкл") + "</span>";
                h += "<b>" + (r.name || "без имени") + "</b> ";
                h += "<code style='font-size:11px'>" + r.email + "</code></div>";
                h += "<div>";
                h += "<button class='btn btn-sm btn-outline-info me-1' " +
                     "onclick='mailEditRcpt(" + r.id + ")' title='Редактировать'>✏</button>";
                h += "<button class='btn btn-sm btn-outline-danger' " +
                     "onclick='mailDeleteRcpt(" + r.id + ")' title='Удалить'>✕</button>";
                h += "</div></div>";
            });
        }
        document.getElementById("mailRcptList").innerHTML = h;
    });
}

function mailSaveSmtp(){
    var data = {
        smtp_server: document.getElementById("mailSmtpServer").value.trim(),
        smtp_port:   document.getElementById("mailSmtpPort").value.trim() || "587",
        smtp_user:   document.getElementById("mailSmtpUser").value.trim(),
        from_name:   document.getElementById("mailFromName").value.trim() || "TRASSIR Monitor",
        from_addr:   document.getElementById("mailFromAddr").value.trim(),
        monitor_url: document.getElementById("mailMonitorUrl").value.trim()
    };
    var pass = document.getElementById("mailSmtpPass").value;
    if(pass) data.smtp_pass = pass;

    fetch("/api/mail/settings", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(data)
    }).then(function(r){return r.json()}).then(function(d){
        if(d.ok){ mailShowResult(d.message, "success"); mailLoadSettings(); }
        else mailShowResult(d.error, "danger");
    });
}

function mailSaveEnabled(){
    fetch("/api/mail/settings", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({enabled: document.getElementById("mailEnabled").checked ? "1" : "0"})
    }).then(function(){ mailLoadSettings(); });
}

function mailAddRecipient(){
    var email = document.getElementById("mailNewEmail").value.trim();
    var name  = document.getElementById("mailNewName").value.trim();
    if(!email){ alert("Введите email адрес"); return; }
    fetch("/api/mail/recipients", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({email: email, name: name})
    }).then(function(r){return r.json()}).then(function(d){
        if(d.ok){
            document.getElementById("mailNewEmail").value = "";
            document.getElementById("mailNewName").value = "";
            mailLoadRecipients();
            mailShowResult(d.message, "success");
        } else {
            mailShowResult(d.error, "danger");
        }
    });
}

function mailEditRcpt(dbId){
    fetch("/api/mail/recipients").then(function(r){return r.json()}).then(function(list){
        var r = list.find(function(x){ return x.id === dbId; });
        if(!r) return;
        var newEmail = prompt("Email адрес:", r.email);
        if(newEmail === null) return;
        var newName = prompt("Имя:", r.name || "");
        if(newName === null) return;
        var data = {id: dbId, name: newName || "", enabled: r.enabled,
                    warning: r.warning, critical: r.critical, info: r.info};
        if(newEmail.trim() && newEmail.trim() !== r.email) data.email = newEmail.trim();
        fetch("/api/mail/recipients", {
            method: "PUT",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify(data)
        }).then(function(r){return r.json()}).then(function(d){
            if(d.ok) mailLoadRecipients();
            else mailShowResult(d.error, "danger");
        });
    });
}

function mailDeleteRcpt(id){
    if(confirm("Удалить получателя?"))
        fetch("/api/mail/recipients?id=" + id, {method: "DELETE"})
        .then(function(){ mailLoadRecipients(); });
}

function mailTest(){
    var e = document.getElementById("mailResult");
    e.style.display = "block";
    e.className = "mt-2 alert alert-info";
    e.textContent = "Отправка тестового письма...";
    fetch("/api/mail/test", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: "{}"
    }).then(function(r){return r.json()}).then(function(d){
        e.className = "mt-2 alert alert-" + (d.ok ? "success" : "danger");
        e.textContent = d.ok ? d.message : d.error;
        setTimeout(function(){ e.style.display = "none"; }, 6000);
    });
}

function mailShowResult(msg, type){
    var e = document.getElementById("mailResult");
    e.style.display = "block";
    e.className = "mt-2 alert alert-" + type;
    e.textContent = msg;
    setTimeout(function(){ e.style.display = "none"; }, 5000);
}

mailRefresh();
</script>
'''

# Ищем блок "Список серверов" и вставляем карточку ПЕРЕД НИМ
search = '    <!-- Список серверов -->'
if search in content:
    content = content.replace(search, mail_card + '\n    ' + search)
    print("    ✓ Карточка Email добавлена перед 'Список серверов'")
else:
    first_col_end = content.find('</div>\n\n    <!-- Список серверов -->')
    if first_col_end != -1:
        content = content[:first_col_end] + mail_card + content[first_col_end:]
        print("    ✓ Карточка Email добавлена")
    else:
        print("    ❌ Не найдено место для вставки в settings.html")

with open(path, 'w') as f:
    f.write(content)
PYHTML

    echo "    ✓ settings.html обновлён"
fi

echo ""
echo -e "${GREEN}✅ Веб-интерфейс обновлён${NC}"
echo ""

# ============================================
# ШАГ 5: SYSTEMD СЕРВИС
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [5/7] СОЗДАНИЕ SYSTEMD СЕРВИСА             ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

cat > "/etc/systemd/system/$SERVICE_MAIL.service" << SERVEOF
[Unit]
Description=TRASSIR Monitor Mail Notifier
Documentation=https://github.com/trassir-monitor
After=$SERVICE_MAIN.service
Requires=$SERVICE_MAIN.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$VENV_PYTHON $MAILBOT_PY
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/mailbot.log
StandardError=append:$LOG_DIR/mailbot-error.log

[Install]
WantedBy=multi-user.target
SERVEOF

touch "$LOG_DIR/mailbot.log" "$LOG_DIR/mailbot-error.log" 2>/dev/null
chown www-data:www-data "$LOG_DIR/mailbot.log" "$LOG_DIR/mailbot-error.log" 2>/dev/null || true

systemctl daemon-reload
systemctl enable "$SERVICE_MAIL" 2>/dev/null

echo "  • Сервис создан: /etc/systemd/system/$SERVICE_MAIL.service"
echo "  • Лог:   $LOG_DIR/mailbot.log"
echo "  • Автозапуск: включён"
echo ""
echo -e "${GREEN}✅ Systemd сервис создан${NC}"
echo ""

# ============================================
# ШАГ 6: ЗАПУСК
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [6/7] ЗАПУСК СЕРВИСОВ                      ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Перезапуск TRASSIR Monitor..."
systemctl restart "$SERVICE_MAIN"
sleep 3

MAIN_STATUS=$(systemctl is-active "$SERVICE_MAIN" 2>/dev/null || echo "inactive")
echo "    Статус: $MAIN_STATUS"

echo "  • Запуск Mail Notifier..."
systemctl start "$SERVICE_MAIL"
sleep 3

MAIL_STATUS=$(systemctl is-active "$SERVICE_MAIL" 2>/dev/null || echo "inactive")
echo "    Статус: $MAIL_STATUS"

if [ "$MAIL_STATUS" != "active" ]; then
    echo ""
    echo -e "  ${RED}❌ Mail Notifier не запустился!${NC}"
    echo "  Проверьте логи:"
    echo "    journalctl -u $SERVICE_MAIL -n 20"
    echo "    tail -20 $LOG_DIR/mailbot-error.log"
fi

echo ""

# ============================================
# ШАГ 7: ТЕСТОВОЕ ПИСЬМО
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [7/7] ОТПРАВКА ТЕСТОВОГО ПИСЬМА            ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Отправка тестового письма..."
source "$INSTALL_DIR/venv/bin/activate"

TEST_RESULT=$($VENV_PYTHON << 'PYEOF'
import sys, os
sys.path.insert(0, '/opt/trassir-monitor')
os.chdir('/opt/trassir-monitor')
from app.mail_bot import (
    get_mail_settings, get_enabled_recipients,
    format_test_email, send_email
)

settings = get_mail_settings()
if not settings.get('smtp_server'):
    print("NO_SMTP")
    sys.exit(0)

recipients = get_enabled_recipients()
if not recipients:
    print("NO_RCPT")
    sys.exit(0)

subject, html_body = format_test_email(settings)
if send_email(recipients[0]['email'], recipients[0].get('name', ''), subject, html_body, settings):
    print("OK:" + recipients[0]['email'])
else:
    print("FAIL")
PYEOF
)

deactivate

case "${TEST_RESULT%%:*}" in
    OK)
        RCPT_ADDR="${TEST_RESULT#OK:}"
        echo -e "  ${GREEN}✅ Тестовое письмо отправлено на: $RCPT_ADDR${NC}"
        echo "     Проверьте почту — должно прийти письмо от TRASSIR Monitor."
        ;;
    NO_SMTP)
        echo -e "  ${YELLOW}⚠ SMTP не настроен${NC}"
        echo "     Настройте через веб-интерфейс: /settings (прокрутите до Email)"
        ;;
    NO_RCPT)
        echo -e "  ${YELLOW}⚠ Нет получателей${NC}"
        echo "     Добавьте получателей через веб-интерфейс /settings"
        ;;
    *)
        echo -e "  ${RED}❌ Тестовое письмо не отправлено${NC}"
        echo ""
        echo "  Возможные причины:"
        echo "    1. Неверный логин/пароль SMTP"
        echo "    2. Для Gmail: нужен пароль приложения, не основной пароль"
        echo "    3. Порт заблокирован файрволом"
        echo "    4. Неверный SMTP сервер"
        echo ""
        echo "  Проверьте:"
        echo "    • Логи: tail -f $LOG_DIR/mailbot.log"
        echo "    • Логи ошибок: tail -20 $LOG_DIR/mailbot-error.log"
        ;;
esac

# ============================================
# ФИНАЛЬНЫЙ ВЫВОД
# ============================================

IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Mail Notifier — УСТАНОВЛЕН! 🎉             ║${NC}"
echo -e "${GREEN}║   v1.1 — Email уведомления + Восстановления   ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}🌐 Веб-управление:${NC}"
echo -e "   ${CYAN}http://${IP}:8080/settings${NC}"
echo -e "   (прокрутите вниз до карточки Email)"
echo ""
echo -e "${BOLD}📋 Управление сервисом:${NC}"
echo -e "   Статус:      ${YELLOW}systemctl status $SERVICE_MAIL${NC}"
echo -e "   Перезапуск:  ${YELLOW}systemctl restart $SERVICE_MAIL${NC}"
echo -e "   Остановка:   ${YELLOW}systemctl stop $SERVICE_MAIL${NC}"
echo -e "   Логи:        ${YELLOW}tail -f $LOG_DIR/mailbot.log${NC}"
echo -e "   Логи ошибок: ${YELLOW}tail -f $LOG_DIR/mailbot-error.log${NC}"
echo ""
echo -e "${BOLD}📁 Файлы:${NC}"
echo -e "   Код демона:  ${CYAN}$MAILBOT_PY${NC}"
echo -e "   Бэкап:       ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "${BOLD}📧 Формат уведомлений:${NC}"
echo -e "   🟢 ВОССТАНОВЛЕНИЕ — канал/сервер вернулся в онлайн"
echo -e "      + время простоя (сколько был недоступен)"
echo -e "   📷 ОТВАЛ КАМЕР — с указанием имён"
echo -e "   🔥 ВЫСОКАЯ НАГРУЗКА CPU"
echo -e "   💾 ПРОБЛЕМА С АРХИВОМ"
echo -e "   💿 ОШИБКА ДИСКОВ"
echo -e "   🔴 КРИТИЧЕСКИЙ АЛЕРТ"
echo -e "   Для каждого: CPU%, камеры онлайн, архив, uptime, отклик"
echo ""
echo -e "${BOLD}⏱ Расчёт времени простоя:${NC}"
echo -e "   При восстановлении камеры — ищется момент её отвала"
echo -e "   При восстановлении сервера — ищется последний offline-алерт"
echo -e "   Пример в письме: 'Время простоя: 2 ч 15 мин'"
echo ""
echo -e "${BOLD}🛡 Защита от спама:${NC}"
echo -e "   • 1 алерт = 1 письмо"
echo -e "   • Повторная отправка исключена"
echo -e "   • Новый алерт после восстановления = новое письмо"
echo ""
echo -e "${BOLD}📮 Поддерживаемые SMTP:${NC}"
echo -e "   • Gmail (smtp.gmail.com:587, нужен App Password)"
echo -e "   • Yandex (smtp.yandex.ru:587)"
echo -e "   • Mail.ru (smtp.mail.ru:587)"
echo -e "   • Корпоративный SMTP любого провайдера"
echo -e "   • SSL/TLS порт 465 и STARTTLS порт 587"
echo ""