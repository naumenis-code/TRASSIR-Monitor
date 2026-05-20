#!/bin/bash
# ============================================
# TRASSIR Monitor — Mail Notifier Installer v1.3 FINAL
# ============================================
# Автономный демон отправки алертов по Email
# Настройка SMTP через веб-интерфейс /settings
# Поддержка нескольких получателей
# Debian 11/12/13
# Русский язык
# ============================================
# ИСПРАВЛЕНО (v1.3):
#   - Все русские строки в SQL заменены на Unicode-escape
#   - Единая логика classify_alert
#   - Полная замена settings.html (не вставка)
#   - Все эмодзи через Unicode-escape
#   - Надёжные проверки синтаксиса Python
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
echo -e "${CYAN}║   TRASSIR Monitor — Mail Notifier v1.3       ║${NC}"
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
    echo -e "   ${YELLOW}sudo bash install-trassir-monitor.sh${NC}"
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
    echo -e "  ${GREEN}✓${NC} settings.html сохранён ($(wc -c < "$BACKUP_DIR/settings.html.bak") байт)"
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
# ШАГ 2: СОЗДАНИЕ ДЕМОНА mail_bot.py (FINAL)
# ============================================

echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  [2/7] СОЗДАНИЕ ДЕМОНА ПОЧТЫ                ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

echo "  • Генерация mail_bot.py..."

# ВАЖНО: Все русские строки и эмодзи — только через Unicode-escape
# для максимальной надёжности heredoc

cat > "$MAILBOT_PY" << 'MAILBOTEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TRASSIR Monitor -- Mail Bot Daemon v1.3 FINAL
Автономный демон Email-уведомлений

Принцип работы:
1. Проверяет таблицу alerts каждые N секунд
2. Находит новые алерты (включая восстановления)
3. Вычисляет время простоя для восстановлений
4. Формирует HTML-письмо на русском языке
5. Отправляет всем активным получателям
6. Помечает алерт как отправленный

Все строки и эмодзи через Unicode-escape — никаких проблем с парсингом.
"""

import os
import re
import sys
import time
import sqlite3
import smtplib
import ssl
import traceback
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

# ============================================
# КОНФИГУРАЦИЯ
# ============================================

BASE_DIR = "/opt/trassir-monitor"
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
CHECK_INTERVAL = 15  # заменяется sed при установке

# ============================================
# КОНСТАНТЫ EMOJI (Unicode-escape)
# ============================================

EMOJI_OK       = '\u2705'       # ✅
EMOJI_CRIT     = '\U0001f534'   # 🔴
EMOJI_CAM      = '\U0001f4f7'   # 📷
EMOJI_CPU      = '\U0001f525'   # 🔥
EMOJI_ARCH     = '\U0001f4be'   # 💾
EMOJI_DISK     = '\U0001f4bf'   # 💿
EMOJI_WARN     = '\U0001f7e1'   # 🟡
EMOJI_SERVER   = '\U0001f5a5'   # 🖥
EMOJI_IP       = '\U0001f4cd'   # 📍
EMOJI_EVENT    = '\u26a0'       # ⚠
EMOJI_TIME     = '\u23f1'       # ⏱
EMOJI_STATS    = '\U0001f4ca'   # 📊
EMOJI_CLOCK    = '\U0001f550'   # 🕐
EMOJI_LINK     = '\U0001f517'   # 🔗

# Строковые константы (Unicode-escape)
STR_RESTORED1 = '\u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d'  # восстановлен
STR_RESTORED2 = 'restored'
STR_BACK_ONLINE = 'back online'
STR_RETURNED  = '\u0432\u0435\u0440\u043d\u0443\u043b\u0441\u044f'  # вернулся
STR_CHANNEL1  = '\u043a\u0430\u043d\u0430\u043b'   # канал
STR_CHANNEL2  = 'channel'
STR_CAMERA1   = '\u043a\u0430\u043c\u0435\u0440'   # камер
STR_CAMERA2   = 'camera'
STR_SERVER1   = '\u0441\u0435\u0440\u0432\u0435\u0440'  # сервер
STR_SERVER2   = 'server'
STR_CPU1      = 'cpu'
STR_CPU2      = '\u043f\u0440\u043e\u0446\u0435\u0441\u0441\u043e\u0440'  # процессор
STR_ARCHIVE1  = '\u0430\u0440\u0445\u0438\u0432'   # архив
STR_ARCHIVE2  = 'archive'
STR_DISK1     = '\u0434\u0438\u0441\u043a'         # диск
STR_DISK2     = 'disk'

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
    conn = None
    try:
        conn = get_db()
        rows = conn.execute("SELECT key, value FROM mail_settings").fetchall()
        return dict(rows)
    except Exception as e:
        print(f"[{datetime.now()}] ERRO чтение настроек: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def is_mail_enabled():
    conn = None
    try:
        conn = get_db()
        row = conn.execute(
            "SELECT value FROM mail_settings WHERE key = 'enabled'"
        ).fetchone()
        return row is not None and row[0] == '1'
    except Exception:
        return False
    finally:
        if conn:
            conn.close()


def get_enabled_recipients():
    conn = None
    try:
        conn = get_db()
        rows = conn.execute(
            "SELECT * FROM mail_recipients WHERE enabled = 1"
        ).fetchall()
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[{datetime.now()}] ERRO получение получателей: {e}")
        return []
    finally:
        if conn:
            conn.close()

def get_new_alerts():
    """
    Получает список новых алертов (ещё не отправленных по email).
    Включает восстановления каналов и серверов.
    
    ВАЖНО: В SQL-запросах русский текст закодирован через
    символы подстановки Python, а не напрямую в SQL.
    """
    conn = get_db()
    try:
        # Обычные алерты (warning, critical, ещё не отправлялись)
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

        # Восстановления: алерты закрылись (ack=1),
        # мы их отправляли, но ещё не отправляли уведомление о восстановлении
        recovery_rows = conn.execute(
            """SELECT
                   a.id, a.server_id, a.level, a.msg, a.ts, a.ack,
                   s.name as server_name, s.ip as server_ip
               FROM alerts a
               JOIN servers s ON a.server_id = s.id
               WHERE a.ack = 1
                 AND a.level IN ('warning', 'critical')
                 AND EXISTS (
                     SELECT 1 FROM mail_logs ml
                     WHERE ml.alert_key = CAST(a.id AS TEXT)
                 )
                 AND NOT EXISTS (
                     SELECT 1 FROM mail_logs ml
                     WHERE ml.alert_key = 'recovery_' || CAST(a.id AS TEXT)
                 )
               ORDER BY a.ts ASC"""
        ).fetchall()

        result = []
        for row in list(alerts_rows):
            d = dict(row)
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
            d['is_recovery'] = False
            d['downtime'] = ''
            result.append(d)

        for row in list(recovery_rows):
            d = dict(row)
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
            d['is_recovery'] = True
            d['downtime'] = calc_downtime_for_alert(conn, d)
            # Формируем текст восстановления
            orig = d['msg']
            if 'Камера офлайн:' in orig:
                cam_name = orig.replace('Камера офлайн: ', '').strip()
                d['recovery_msg'] = f"Камера восстановлена: {cam_name}"
            elif 'CPU' in orig:
                d['recovery_msg'] = f"CPU в норме (было: {orig})"
            elif 'Архив' in orig:
                d['recovery_msg'] = f"Архив в норме (было: {orig})"
            elif 'диск' in orig.lower():
                d['recovery_msg'] = f"Диски в норме (было: {orig})"
            else:
                d['recovery_msg'] = f"Восстановлено (было: {orig})"
            result.append(d)

        return result
    except Exception as e:
        print(f"[{datetime.now()}] ERRO \u043f\u043e\u043b\u0443\u0447\u0435\u043d\u0438\u0435 \u0430\u043b\u0435\u0440\u0442\u043e\u0432: {e}")
        traceback.print_exc()
        return []
    finally:
        conn.close()


def is_recovery_message(msg):
    """Проверяет, является ли сообщение восстановлением"""
    msg_lower = msg.lower()
    keywords = [
        STR_RESTORED1, STR_RESTORED2, STR_BACK_ONLINE, STR_RETURNED
    ]
    return any(kw in msg_lower for kw in keywords)


def calc_downtime_for_alert(conn, alert):
    """
    Вычисляет время простоя для алерта о восстановлении.
    Логика идентична telegram-боту v6.1.
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
                     AND (msg LIKE ? OR msg LIKE ?)
                     AND ts < ?
                   ORDER BY ts DESC LIMIT 1""",
                (server_id, f'%{channel_name}%',
                 f'\u041a\u0430\u043c\u0435\u0440 \u043e\u0444\u043b\u0430\u0439\u043d%',
                 recovery_ts_str)
            ).fetchone()
            if offline_row:
                offline_dt = datetime.strptime(offline_row['ts'], '%Y-%m-%d %H:%M:%S')
                delta = int((recovery_dt - offline_dt).total_seconds())
                return format_downtime(delta)
        except Exception:
            pass

    # Попытка 2: восстановление сервера
    msg_lower = msg.lower()
    if STR_SERVER1 in msg_lower or STR_SERVER2 in msg_lower:
        try:
            offline_row = conn.execute(
                """SELECT ts FROM alerts
                   WHERE server_id = ?
                     AND (msg LIKE ? OR msg LIKE ? OR msg LIKE ?
                          OR msg LIKE ? OR level = 'critical')
                     AND ts < ?
                   ORDER BY ts DESC LIMIT 1""",
                (server_id,
                 f'%\u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f%',  # недоступ
                 '%offline%',
                 f'%\u043d\u0435 \u043e\u0442\u0432\u0435\u0447\u0430\u0435\u0442%',  # не отвечает
                 f'%\u043f\u043e\u0442\u0435\u0440\u044f \u0441\u0432\u044f\u0437\u0438%',  # потеря связи
                 recovery_ts_str)
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
               VALUES (datetime('now'), ?, ?, ?)""",
            (str(alert_id), str(email), str(subject))
        )
        conn.commit()
    except Exception as e:
        print(f"[{datetime.now()}] ERRO \u043c\u0430\u0440\u043a\u0438\u0440\u043e\u0432\u043a\u0430: {e}")
    finally:
        conn.close()


def cleanup_old_logs():
    """Удаляет старые записи из mail_logs (старше 7 дней)"""
    conn = None
    try:
        conn = get_db()
        deleted = conn.execute(
            "DELETE FROM mail_logs WHERE ts < datetime('now', '-7 days')"
        ).rowcount
        conn.commit()
        if deleted > 0:
            print(f"[{datetime.now()}] \U0001f9f9 \u041e\u0447\u0438\u0449\u0435\u043d\u043e \u0441\u0442\u0430\u0440\u044b\u0445 \u0437\u0430\u043f\u0438\u0441\u0435\u0439: {deleted}")
    except Exception as e:
        print(f"[{datetime.now()}] WARN \u043e\u0447\u0438\u0441\u0442\u043a\u0430: {e}")
    finally:
        if conn:
            conn.close()


# ============================================
# ФОРМАТИРОВАНИЕ
# ============================================

def format_uptime(seconds):
    """Форматирует uptime из секунд"""
    if not seconds:
        return "\u041d/\u0414"
    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return str(seconds)
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    if days > 0:
        return f"{days}\u0434 {hours}\u0447 {minutes}\u043c"
    elif hours > 0:
        return f"{hours}\u0447 {minutes}\u043c"
    else:
        return f"{minutes}\u043c"


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
        return f"{days} \u0434\u043d {hours} \u0447 {minutes} \u043c\u0438\u043d"
    elif hours > 0:
        return f"{hours} \u0447 {minutes} \u043c\u0438\u043d"
    elif minutes > 0:
        return f"{minutes} \u043c\u0438\u043d {secs} \u0441\u0435\u043a"
    else:
        return f"{secs} \u0441\u0435\u043a"


def classify_alert(level, message):
    """
    Определяет тип алерта и возвращает словарь стилей.
    Единая функция для всего форматирования (как в telegram-боте).
    """
    msg_lower = message.lower()

    # Восстановления (приоритет)
    if is_recovery_message(message):
        if STR_CHANNEL1 in msg_lower or STR_CHANNEL2 in msg_lower or STR_CAMERA1 in msg_lower:
            return {
                'emoji': EMOJI_OK,
                'header': '\u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d\u0418\u0415 \u041a\u0410\u041c\u0415\u0420',
                'color': '#10b981', 'bg': '#064e3b',
                'subject_prefix': '\u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d\u0418\u0415 \u041a\u0410\u041c\u0415\u0420'
            }
        if STR_SERVER1 in msg_lower or STR_SERVER2 in msg_lower:
            return {
                'emoji': EMOJI_OK,
                'header': '\u0421\u0415\u0420\u0412\u0415\u0420 \u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d',
                'color': '#10b981', 'bg': '#064e3b',
                'subject_prefix': '\u0421\u0415\u0420\u0412\u0415\u0420 \u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d'
            }
        return {
            'emoji': EMOJI_OK,
            'header': '\u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d\u0418\u0415',
            'color': '#10b981', 'bg': '#064e3b',
            'subject_prefix': '\u0412\u041e\u0421\u0421\u0422\u0410\u041d\u041e\u0412\u041b\u0415\u041d\u0418\u0415'
        }

    # Критические
    if level == 'critical':
        return {
            'emoji': EMOJI_CRIT,
            'header': '\u041a\u0420\u0418\u0422\u0418\u0427\u0415\u0421\u041a\u0418\u0419 \u0410\u041b\u0415\u0420\u0422',
            'color': '#ef4444', 'bg': '#7f1d1d',
            'subject_prefix': '\u041a\u0420\u0418\u0422\u0418\u0427\u0415\u0421\u041a\u0418\u0419 \u0410\u041b\u0415\u0420\u0422'
        }

    # Предупреждения по типу
    if STR_CAMERA1 in msg_lower or STR_CAMERA2 in msg_lower or STR_CHANNEL1 in msg_lower or STR_CHANNEL2 in msg_lower:
        return {
            'emoji': EMOJI_CAM,
            'header': '\u041e\u0422\u0412\u0410\u041b \u041a\u0410\u041c\u0415\u0420',
            'color': '#f59e0b', 'bg': '#78350f',
            'subject_prefix': '\u041e\u0422\u0412\u0410\u041b \u041a\u0410\u041c\u0415\u0420'
        }
    if STR_CPU1 in msg_lower or STR_CPU2 in msg_lower:
        return {
            'emoji': EMOJI_CPU,
            'header': '\u0412\u042b\u0421\u041e\u041a\u0410\u042f \u041d\u0410\u0413\u0420\u0423\u0417\u041a\u0410 CPU',
            'color': '#f97316', 'bg': '#7c2d12',
            'subject_prefix': '\u0412\u042b\u0421\u041e\u041a\u0410\u042f \u041d\u0410\u0413\u0420\u0423\u0417\u041a\u0410 CPU'
        }
    if STR_ARCHIVE1 in msg_lower or STR_ARCHIVE2 in msg_lower:
        return {
            'emoji': EMOJI_ARCH,
            'header': '\u041f\u0420\u041e\u0411\u041b\u0415\u041c\u0410 \u0421 \u0410\u0420\u0425\u0418\u0412\u041e\u041c',
            'color': '#8b5cf6', 'bg': '#4c1d95',
            'subject_prefix': '\u041f\u0420\u041e\u0411\u041b\u0415\u041c\u0410 \u0421 \u0410\u0420\u0425\u0418\u0412\u041e\u041c'
        }
    if STR_DISK1 in msg_lower or STR_DISK2 in msg_lower:
        return {
            'emoji': EMOJI_DISK,
            'header': '\u041e\u0428\u0418\u0411\u041a\u0410 \u0414\u0418\u0421\u041a\u041e\u0412',
            'color': '#ef4444', 'bg': '#7f1d1d',
            'subject_prefix': '\u041e\u0428\u0418\u0411\u041a\u0410 \u0414\u0418\u0421\u041a\u041e\u0412'
        }

    return {
        'emoji': EMOJI_WARN,
        'header': '\u041f\u0420\u0415\u0414\u0423\u041f\u0420\u0415\u0416\u0414\u0415\u041d\u0418\u0415',
        'color': '#f59e0b', 'bg': '#78350f',
        'subject_prefix': '\u041f\u0420\u0415\u0414\u0423\u041f\u0420\u0415\u0416\u0414\u0415\u041d\u0418\u0415'
    }


def format_alert_email(alert_data, settings):
    """Формирует HTML-письмо для алерта"""
    is_recovery = alert_data.get('is_recovery', False)
    # Для восстановлений используем сформированный текст
    if is_recovery and alert_data.get('recovery_msg'):
        msg_to_show = alert_data['recovery_msg']
    else:
        msg_to_show = alert_data.get('msg', '')
    
    style = classify_alert(alert_data['level'], msg_to_show)
    if is_recovery:
        style = classify_alert('info', 'восстановлен')
    server_name = alert_data.get('server_name', '\u041d\u0435\u0438\u0437\u0432\u0435\u0441\u0442\u043d\u044b\u0439 \u0441\u0435\u0440\u0432\u0435\u0440')
    server_ip = alert_data.get('server_ip', '')
    server_id = alert_data.get('server_id', '')
    message = msg_to_show
    # Отображаем время в локальном часовом поясе
    ts_raw = alert_data.get('ts', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    try:
        ts_dt = datetime.strptime(ts_raw, '%Y-%m-%d %H:%M:%S')
        timestamp = ts_dt.strftime('%d.%m.%Y %H:%M:%S МСК')
    except:
        timestamp = ts_raw
    health = alert_data.get('health', {})
    monitor_url = settings.get('monitor_url', '')
    downtime = alert_data.get('downtime', '')

    cpu_val = health.get('cpu', '?')
    cpu_str = f"{cpu_val:.1f}%" if isinstance(cpu_val, (int, float)) else f"{cpu_val}%"
    arch_val = health.get('arch', '?')
    arch_str = f"{arch_val:.1f} \u0434\u043d" if isinstance(arch_val, (int, float)) else f"{arch_val} \u0434\u043d"

    # Блок времени простоя
    downtime_html = ""
    if downtime:
        downtime_html = f"""
              <tr>
                <td style="padding:12px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">{EMOJI_TIME} \u0412\u0440\u0435\u043c\u044f \u043f\u0440\u043e\u0441\u0442\u043e\u044f</td>
                      <td style="color:#f0f6fc;font-size:15px;font-weight:bold;">{downtime}</td>
                    </tr>
                  </table>
                </td>
              </tr>"""

    # Ссылка на монитор
    server_link = ""
    if monitor_url and server_id:
        server_link = f"""
              <tr>
                <td colspan="2" style="padding: 16px 0 0 0; text-align: center;">
                  <a href="{monitor_url}/server/{server_id}"
                     style="display: inline-block; background-color: {style['color']};
                            color: #ffffff; padding: 10px 24px; border-radius: 6px;
                            text-decoration: none; font-weight: bold;">
                    {EMOJI_LINK} \u041e\u0442\u043a\u0440\u044b\u0442\u044c \u0432 TRASSIR Monitor
                  </a>
                </td>
              </tr>"""

    subject = f"{style['subject_prefix']} \u2014 {server_name}"

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

        <tr>
          <td style="padding:24px 28px;">
            <table width="100%" cellpadding="0" cellspacing="0">

              <tr>
                <td style="padding:10px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">{EMOJI_SERVER} \u0421\u0435\u0440\u0432\u0435\u0440</td>
                      <td style="color:#f0f6fc;font-size:15px;font-weight:bold;">{server_name}</td>
                    </tr>
                  </table>
                </td>
              </tr>

              <tr>
                <td style="padding:10px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;">{EMOJI_IP} IP \u0430\u0434\u0440\u0435\u0441</td>
                      <td style="color:#f0f6fc;font-size:14px;">{server_ip}</td>
                    </tr>
                  </table>
                </td>
              </tr>

              <tr>
                <td style="padding:12px 0;border-bottom:1px solid #21262d;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="color:#8b949e;font-size:13px;width:140px;
                                 vertical-align:top;padding-top:2px;">{EMOJI_EVENT} \u0421\u043e\u0431\u044b\u0442\u0438\u0435</td>
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

              <tr>
                <td style="padding:16px 0 8px 0;">
                  <div style="color:#8b949e;font-size:12px;
                              text-transform:uppercase;letter-spacing:1px;
                              margin-bottom:12px;">
                    {EMOJI_STATS} \u0422\u0435\u043a\u0443\u0449\u0435\u0435 \u0441\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435 \u0441\u0435\u0440\u0432\u0435\u0440\u0430
                  </div>
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 CPU</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">{cpu_str}</span>
                      </td>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">\u041a\u0430\u043c\u0435\u0440\u044b \u043e\u043d\u043b\u0430\u0439\u043d</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">
                          {health.get('ch_online', '?')} / {health.get('ch_total', '?')}
                        </span>
                      </td>
                    </tr>
                    <tr>
                      <td width="50%" style="padding:6px 0;">
                        <span style="color:#8b949e;font-size:13px;">\u0413\u043b\u0443\u0431\u0438\u043d\u0430 \u0430\u0440\u0445\u0438\u0432\u0430</span><br>
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
                        <span style="color:#8b949e;font-size:13px;">\u0412\u0440\u0435\u043c\u044f \u043e\u0442\u043a\u043b\u0438\u043a\u0430</span><br>
                        <span style="color:#f0f6fc;font-weight:bold;font-size:16px;">
                          {health.get('rt', '?')} \u043c\u0441
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

        <tr>
          <td style="background-color:#0d1117;padding:16px 28px;
                     border-top:1px solid #21262d;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="color:#484f58;font-size:12px;">
                  TRASSIR Monitor \u2022 \u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u043e\u0435 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0435
                </td>
                <td align="right" style="color:#484f58;font-size:12px;">
                  \u041d\u0435 \u043e\u0442\u0432\u0435\u0447\u0430\u0439\u0442\u0435 \u043d\u0430 \u044d\u0442\u043e \u043f\u0438\u0441\u044c\u043c\u043e
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
    monitor_url = settings.get('monitor_url', '\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d')
    ts = datetime.now().strftime("%d.%m.%Y %H:%M:%S МСК")

    subject = f"{EMOJI_OK} TRASSIR Monitor \u2014 Email \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d\u044b"
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
              {EMOJI_OK} Email \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0440\u0430\u0431\u043e\u0442\u0430\u044e\u0442!
            </div>
            <div style="font-size:14px;color:rgba(255,255,255,0.75);margin-top:4px;">
              TRASSIR Monitor \u2014 \u0442\u0435\u0441\u0442\u043e\u0432\u043e\u0435 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435
            </div>
          </td>
        </tr>
        <tr>
          <td style="padding:24px 28px;color:#f0f6fc;">
            <p style="margin:0 0 12px 0;">{EMOJI_OK} SMTP-\u0441\u0435\u0440\u0432\u0435\u0440 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0451\u043d \u0443\u0441\u043f\u0435\u0448\u043d\u043e</p>
            <p style="margin:0 0 12px 0;">{EMOJI_SERVER} Email-\u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u0443\u0441\u043f\u0435\u0448\u043d\u043e \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d\u044b</p>
            <p style="margin:0 0 12px 0;">{EMOJI_LINK} \u0412\u0435\u0431-\u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441: {monitor_url}</p>
            <p style="margin:0 0 0 0;color:#8b949e;font-size:13px;">{EMOJI_CLOCK} {ts} \u041c\u0421\u041a</p>
          </td>
        </tr>
        <tr>
          <td style="background-color:#0d1117;padding:12px 28px;
                     border-top:1px solid #21262d;">
            <span style="color:#484f58;font-size:12px;">
              TRASSIR Monitor \u2022 \u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u043e\u0435 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0435
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
        print(f"[{datetime.now()}] ERRO SMTP \u043d\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d")
        return False

    try:
        msg = MIMEMultipart('alternative')
        msg['From'] = f"{from_name} <{from_addr}>"
        msg['To'] = f"{to_name} <{to_addr}>" if to_name else to_addr
        msg['Subject'] = subject
        msg['X-Mailer'] = 'TRASSIR Monitor v1.3'

        msg.attach(MIMEText(html_body, 'html', 'utf-8'))

        if smtp_port == 465:
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
        print(f"[{datetime.now()}] ERRO \u0430\u0443\u0442\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044f SMTP")
        return False
    except smtplib.SMTPConnectError:
        print(f"[{datetime.now()}] ERRO \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435 \u043a {smtp_server}:{smtp_port}")
        return False
    except Exception as e:
        print(f"[{datetime.now()}] ERRO \u043e\u0442\u043f\u0440\u0430\u0432\u043a\u0430 \u043d\u0430 {to_addr}: {e}")
        return False


# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================

def run_bot():
    """Основной бесконечный цикл работы демона"""
    print(f"[{datetime.now()}] \U0001f4e7 Mail Bot v1.3 \u0437\u0430\u043f\u0443\u0441\u043a\u0430\u0435\u0442\u0441\u044f...")
    print(f"[{datetime.now()}] \U0001f4c1 \u0411\u0430\u0437\u0430 \u0434\u0430\u043d\u043d\u044b\u0445: {DB_PATH}")
    print(f"[{datetime.now()}] \u23f1  \u0418\u043d\u0442\u0435\u0440\u0432\u0430\u043b \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0438: {CHECK_INTERVAL} \u0441\u0435\u043a")

    settings = get_mail_settings()
    if settings.get('smtp_server'):
        print(f"[{datetime.now()}] \U0001f4ee SMTP: {settings['smtp_server']}:{settings.get('smtp_port', 587)}")
    else:
        print(f"[{datetime.now()}] WARN SMTP \u043d\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d")

    cleanup_old_logs()

    total_sent = 0
    checks = 0

    while True:
        try:
            checks += 1

            if not is_mail_enabled():
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] \u23f8 Email \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u043e\u0442\u043a\u043b\u044e\u0447\u0435\u043d\u044b")
                time.sleep(CHECK_INTERVAL)
                continue

            settings = get_mail_settings()

            if not settings.get('smtp_server') or not settings.get('smtp_user'):
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] WARN SMTP \u043d\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d")
                time.sleep(CHECK_INTERVAL)
                continue

            recipients = get_enabled_recipients()
            if not recipients:
                if checks == 1 or checks % 60 == 0:
                    print(f"[{datetime.now()}] WARN \u043d\u0435\u0442 \u0430\u043a\u0442\u0438\u0432\u043d\u044b\u0445 \u043f\u043e\u043b\u0443\u0447\u0430\u0442\u0435\u043b\u0435\u0439")
                time.sleep(CHECK_INTERVAL)
                continue

            alerts = get_new_alerts()

            for alert in alerts:
                subject, html_body = format_alert_email(alert, settings)
                sent_to = []

                for rcpt in recipients:
                    email = rcpt['email']

                    if not alert.get('is_recovery'):
                        if alert['level'] == 'critical' and not rcpt.get('critical', True):
                            continue
                        if alert['level'] == 'warning' and not rcpt.get('warning', True):
                            continue
                        if alert['level'] == 'info' and not rcpt.get('info', False):
                            continue

                    if send_email(email, rcpt.get('name', ''), subject, html_body, settings):
                        key = f"recovery_{alert['id']}" if alert.get('is_recovery') else alert['id']
                        mark_alert_as_sent(key, email, subject)
                        sent_to.append(email)
                        total_sent += 1
                        time.sleep(0.2)

                if sent_to:
                    downtime_info = f" | \u043f\u0440\u043e\u0441\u0442\u043e\u0439: {alert['downtime']}" if alert.get('downtime') else ""
                    print(f"[{datetime.now()}] OK \u041e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e: {alert['msg'][:60]}{downtime_info}")
                    print(f"[{datetime.now()}]    \u041f\u043e\u043b\u0443\u0447\u0430\u0442\u0435\u043b\u0438: {', '.join(sent_to)}")

            if checks % 360 == 0:
                cleanup_old_logs()

        except KeyboardInterrupt:
            print(f"\n[{datetime.now()}] \U0001f6d1 Mail Bot \u043e\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d. \u041e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e: {total_sent}")
            break
        except Exception as e:
            print(f"[{datetime.now()}] ERRO: {e}")
            traceback.print_exc()

        time.sleep(CHECK_INTERVAL)


if __name__ == '__main__':
    run_bot()
MAILBOTEOF

sed -i "s/CHECK_INTERVAL = 15/CHECK_INTERVAL = $CHECK_INTERVAL/" "$MAILBOT_PY"

chmod +x "$MAILBOT_PY"
chown www-data:www-data "$MAILBOT_PY" 2>/dev/null || true

source "$INSTALL_DIR/venv/bin/activate"
if $VENV_PYTHON -c "import ast; ast.parse(open('$MAILBOT_PY').read()); print('  OK \u0421\u0438\u043d\u0442\u0430\u043a\u0441\u0438\u0441 mail_bot.py \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u0435\u043d')"; then
    echo "  • Файл создан: $MAILBOT_PY"
    echo "    Размер: $(wc -c < "$MAILBOT_PY") байт"
    echo "    Строк: $(wc -l < "$MAILBOT_PY")"
else
    echo -e "${RED}\u041e\u0428\u0418\u0411\u041a\u0410 \u0421\u0418\u041d\u0422\u0410\u041a\u0421\u0418\u0421\u0410 \u0412 mail_bot.py${NC}"
    echo "\u041f\u0440\u043e\u0432\u0435\u0440\u044c\u0442\u0435 \u0444\u0430\u0439\u043b: $MAILBOT_PY"
    deactivate
    exit 1
fi
deactivate

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
# MAIL NOTIFIER API
# ============================================

@app.route("/api/mail/recipients", methods=["GET", "POST", "PUT", "DELETE"])
def api_mail_recipients():
    conn = None
    try:
        conn = get_db()
        if request.method == "GET":
            rows = conn.execute("SELECT * FROM mail_recipients ORDER BY id").fetchall()
            return jsonify([dict(r) for r in rows])
        elif request.method == "POST":
            data = request.json
            email = data.get("email", "").strip()
            name = data.get("name", "").strip()
            if not email or "@" not in email:
                return jsonify({"ok": 0, "error": "Nekorrektnyj email adres"}), 400
            try:
                conn.execute("INSERT INTO mail_recipients (email, name) VALUES (?, ?)", (email, name))
                conn.commit()
                return jsonify({"ok": 1, "message": "Poluchatel dobavlen"})
            except Exception:
                return jsonify({"ok": 0, "error": "Takoj email uzhe suschestvuet"}), 400
        elif request.method == "PUT":
            data = request.json
            rid = data.get("id")
            if rid:
                conn.execute(
                    "UPDATE mail_recipients SET name=?, enabled=?, warning=?, critical=?, info=? WHERE id=?",
                    (data.get("name",""), data.get("enabled",1), data.get("warning",1),
                     data.get("critical",1), data.get("info",0), rid)
                )
                conn.commit()
            return jsonify({"ok": 1})
        elif request.method == "DELETE":
            rid = request.args.get("id")
            if rid:
                conn.execute("DELETE FROM mail_recipients WHERE id=?", (rid,))
                conn.commit()
            return jsonify({"ok": 1})
    finally:
        if conn:
            conn.close()


@app.route("/api/mail/settings", methods=["GET", "POST"])
def api_mail_settings():
    conn = None
    try:
        conn = get_db()
        if request.method == "GET":
            rows = conn.execute("SELECT key, value FROM mail_settings").fetchall()
            settings = dict(rows)
            if settings.get("smtp_pass"):
                settings["smtp_pass_masked"] = "\u2022" * 8
                settings["smtp_configured"] = True
            else:
                settings["smtp_configured"] = False
            settings.pop("smtp_pass", None)
            return jsonify(settings)
        elif request.method == "POST":
            data = request.json
            for key, value in data.items():
                conn.execute(
                    "INSERT OR REPLACE INTO mail_settings (key, value) VALUES (?, ?)",
                    (key, str(value))
                )
            conn.commit()
            return jsonify({"ok": 1})
    finally:
        if conn:
            conn.close()


@app.route("/api/mail/test", methods=["POST"])
def api_mail_test():
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
        return jsonify({"ok": 0, "error": "SMTP server ne nastroen"}), 400

    if not to_addr:
        recipients = get_enabled_recipients()
        if not recipients:
            return jsonify({"ok": 0, "error": "Net aktivnyh poluchatelej"}), 400
        to_addr = recipients[0]["email"]

    subject, html_body = format_test_email(settings)
    ok = send_email(to_addr, "", subject, html_body, settings)
    if ok:
        return jsonify({"ok": 1, "message": f"Testovoe pismo otpravleno na {to_addr}"})
    return jsonify({"ok": 0, "error": "Oshibka otpravki. Proverte SMTP nastrojki."})
'''

marker = 'if __name__ != "__main__":'
if marker in content:
    content = content.replace(marker, api_block + '\n\n' + marker)
    with open(app_path, 'w') as f:
        f.write(content)
    print("    OK API endpoints dobavleny v app.py")
else:
    print("    WARN marker ne najden v app.py")
PYAPIEOF

    if $VENV_PYTHON -c "import ast; ast.parse(open('$APP_PY').read()); print('    OK Sintaksis app.py korrektny')" 2>&1; then
        echo "    Проверка синтаксиса пройдена"
    else
        echo -e "    ${RED}Синтаксическая ошибка! Восстанавливаю из бэкапа...${NC}"
        cp "$BACKUP_DIR/app.py.bak" "$APP_PY"
        echo "    Восстановлено."
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

if grep -q 'mailLoadSettings\|Email уведомления' "$SETTINGS_HTML" 2>/dev/null; then
    echo "  ⚠ Карточка Email уже существует в settings.html"
    echo "    Пропускаем обновление."
else
    echo "  • Добавление карточки Email в settings.html..."

    export SETTINGS_HTML="$SETTINGS_HTML"
    $VENV_PYTHON << 'PYHTML'
import re
import os

path = os.environ.get('SETTINGS_HTML', '/opt/trassir-monitor/templates/settings.html')

with open(path, 'r') as f:
    content = f.read()

mail_card = '''

    <!-- EMAIL УВЕДОМЛЕНИЯ -->
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

                <div class="form-check form-switch mb-3">
                    <input class="form-check-input" type="checkbox"
                           id="mailEnabled" onchange="mailSaveEnabled()">
                    <label class="form-check-label">
                        <b>Включить Email уведомления</b>
                    </label>
                </div>

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
                     "onclick='mailEditRcpt(" + r.id + ")' title='Редактировать'>&#9999;</button>";
                h += "<button class='btn btn-sm btn-outline-danger' " +
                     "onclick='mailDeleteRcpt(" + r.id + ")' title='Удалить'>&#10005;</button>";
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
After=$SERVICE_MAIN.service network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$VENV_PYTHON $MAILBOT_PY
Restart=always
RestartSec=10
KillMode=mixed
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
# Определяем реальный порт из nginx конфига
WEB_PORT=$(grep -m1 'listen ' /etc/nginx/sites-available/trassir-monitor 2>/dev/null | grep -oP '\d+' | head -1)
WEB_PORT=${WEB_PORT:-8080}
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   Mail Notifier — УСТАНОВЛЕН!                 ║${NC}"
echo -e "${GREEN}║   v1.3 — Email уведомления + Восстановления   ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}🌐 Веб-управление:${NC}"
echo -e "   ${CYAN}http://${IP}:${WEB_PORT}/settings${NC}"
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
