from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import Session, sessionmaker

from ..config import settings
from .base import Base


def _build_engine():
    url = settings.database_url
    connect_args = {}
    if url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    return create_engine(url, connect_args=connect_args, pool_pre_ping=True)


engine = _build_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db() -> None:
    # Import models so metadata is populated before create_all.
    from .. import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
    _drop_legacy_tables()


def _drop_legacy_tables() -> None:
    """Remove tables that are no longer part of the SQLAlchemy schema."""
    keep_tables = set(Base.metadata.tables.keys())
    inspector = inspect(engine)
    legacy_tables = [
        name for name in inspector.get_table_names() if name not in keep_tables
    ]
    if not legacy_tables:
        return

    with engine.begin() as conn:
        for table_name in legacy_tables:
            conn.execute(text(f'DROP TABLE IF EXISTS "{table_name}" CASCADE'))


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
