import asyncio
import json
import sqlite3
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import pymysql
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from listening_common import RUNTIME, ServiceSettings, model_json, private_value, require_service
from .catalog import CATALOG, SYSTEM
from .guard import UnsafeSQL, validate_sql

cfg = ServiceSettings()
app = FastAPI(title="听见 · 运营问数")
from request_trace import RequestTraceMiddleware
app.add_middleware(RequestTraceMiddleware,service='operations',rate_limit=60)


class Query(BaseModel):
    question: str = Field(min_length=1, max_length=1000)
    actor_id: str = Field(pattern=r"^\d{1,20}$")


def audit(request_id: str, actor: str, question: str, sql: str, status: str, count: int):
    RUNTIME.mkdir(exist_ok=True)
    with sqlite3.connect(RUNTIME / "operations-audit.sqlite") as db:
        db.execute("CREATE TABLE IF NOT EXISTS queries(id TEXT PRIMARY KEY, actor TEXT, question TEXT, sql TEXT, status TEXT, row_count INTEGER, created_at TEXT)")
        db.execute("INSERT INTO queries VALUES(?,?,?,?,?,?,?)", (request_id, actor, question, sql,
            status, count, datetime.now(timezone.utc).isoformat()))


def execute_readonly(sql: str) -> list[dict]:
    # 执行前再次校验，避免未来绕过生成步骤的代码路径执行不安全 SQL。
    sql, _ = validate_sql(sql)
    password = cfg.listening_reader_password or private_value("LISTENING_READER_PASSWORD", "reader-password")
    connection = pymysql.connect(host=cfg.listening_db_host, port=cfg.listening_db_port,
        user="listening_reader", password=password, database="listening_ops", charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor, connect_timeout=3, read_timeout=5, write_timeout=3)
    with connection:
        with connection.cursor() as cursor:
            cursor.execute("SET time_zone = '+08:00'")
            cursor.execute("SET SESSION MAX_EXECUTION_TIME=3000")
            cursor.execute("START TRANSACTION READ ONLY")
            cursor.execute(sql)
            rows = cursor.fetchmany(101)
        connection.rollback()
    if len(rows) > 100:
        raise UnsafeSQL("结果超过行数上限")
    return [{k: str(v) if isinstance(v, (Decimal, date, datetime)) else v for k, v in row.items()} for row in rows]


@app.get("/health")
def health():
    return {"ok": True, "mode": "readonly-nl2sql", "views": len(CATALOG), "max_rows": 100}


@app.get("/catalog", dependencies=[Depends(require_service)])
def catalog():
    return CATALOG


@app.post("/query", dependencies=[Depends(require_service)])
async def query(req: Query):
    request_id, sql = str(uuid.uuid4()), ""
    try:
        plan = await model_json(cfg, SYSTEM, json.dumps({"question": req.question,
            "today": datetime.now(timezone(timedelta(hours=8))).date().isoformat(),
            "catalog": CATALOG}, ensure_ascii=False))
        if "unsupported" in plan:
            audit(request_id, req.actor_id, req.question, "", "unsupported", 0)
            raise HTTPException(422, str(plan["unsupported"])[:200])
        sql = plan.get("sql", "")
        sql, view = validate_sql(sql)
        rows = await asyncio.to_thread(execute_readonly, sql)
        audit(request_id, req.actor_id, req.question, sql, "completed", len(rows))
        return {"request_id": request_id, "sql": sql, "view": view, "rows": rows,
                "columns": list(rows[0]) if rows else [], "row_count": len(rows),
                "definition": CATALOG[view]["description"], "labels": CATALOG[view]["columns"],
                "mode": "readonly-nl2sql", "data_source": "平台初始化数据（排除本地演示账号）"}
    except UnsafeSQL as error:
        audit(request_id, req.actor_id, req.question, sql, "rejected", 0)
        raise HTTPException(422, str(error)) from None
    except pymysql.MySQLError:
        audit(request_id, req.actor_id, req.question, sql, "database-error", 0)
        raise HTTPException(502, "只读数据查询失败，请检查数据库连接或指标视图") from None
