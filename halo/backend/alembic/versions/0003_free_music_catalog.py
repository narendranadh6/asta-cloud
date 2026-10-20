"""free music catalog replaces YouTube

Tracks now come from Audius, Jamendo and iTunes previews and are identified as
"<source>:<id>". YouTube-specific columns are dropped, and stored YouTube references
(which can no longer be played) are removed.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-21 00:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # YouTube data can't be played without YouTube; remove it rather than keep dead rows.
    op.execute(
        "DELETE FROM playlist_items WHERE track_id IN "
        "(SELECT id FROM track_references WHERE provider = 'youtube')"
    )
    op.execute("DELETE FROM track_references WHERE provider = 'youtube'")
    op.execute("DELETE FROM recommendation_feedback")
    op.execute("UPDATE recommendation_sessions SET result_video_ids = '[]'")

    with op.batch_alter_table("track_references") as batch:
        batch.alter_column("channel_title", new_column_name="artist")
        batch.alter_column("thumbnail_url", new_column_name="artwork_url")
        batch.drop_column("channel_id")
        batch.add_column(sa.Column("album", sa.String(length=300), nullable=True))
        batch.add_column(sa.Column("stream_url", sa.String(length=1000), nullable=True))
        batch.add_column(
            sa.Column("is_preview", sa.Boolean(), server_default=sa.false(), nullable=False)
        )

    with op.batch_alter_table("recommendation_feedback") as batch:
        batch.drop_constraint("uq_feedback_user_video", type_="unique")
        batch.alter_column(
            "video_id",
            new_column_name="track_id",
            type_=sa.String(length=80),
            existing_type=sa.String(length=16),
            existing_nullable=False,
        )
        batch.alter_column("channel_title", new_column_name="artist")
        batch.create_unique_constraint("uq_feedback_user_track", ["user_id", "track_id"])

    with op.batch_alter_table("recommendation_sessions") as batch:
        batch.alter_column("result_video_ids", new_column_name="result_track_ids")

    with op.batch_alter_table("playlists") as batch:
        batch.drop_column("youtube_playlist_id")

    with op.batch_alter_table("artist_preferences") as batch:
        batch.drop_column("youtube_channel_id")


def downgrade() -> None:
    with op.batch_alter_table("artist_preferences") as batch:
        batch.add_column(sa.Column("youtube_channel_id", sa.String(length=64), nullable=True))
    with op.batch_alter_table("playlists") as batch:
        batch.add_column(sa.Column("youtube_playlist_id", sa.String(length=64), nullable=True))
    with op.batch_alter_table("recommendation_sessions") as batch:
        batch.alter_column("result_track_ids", new_column_name="result_video_ids")
    op.execute("DELETE FROM recommendation_feedback")
    with op.batch_alter_table("recommendation_feedback") as batch:
        batch.drop_constraint("uq_feedback_user_track", type_="unique")
        batch.alter_column("artist", new_column_name="channel_title")
        batch.alter_column(
            "track_id",
            new_column_name="video_id",
            type_=sa.String(length=16),
            existing_type=sa.String(length=80),
            existing_nullable=False,
        )
        batch.create_unique_constraint("uq_feedback_user_video", ["user_id", "video_id"])
    op.execute(
        "DELETE FROM playlist_items WHERE track_id IN (SELECT id FROM track_references)"
    )
    op.execute("DELETE FROM track_references")
    with op.batch_alter_table("track_references") as batch:
        batch.drop_column("is_preview")
        batch.drop_column("stream_url")
        batch.drop_column("album")
        batch.add_column(sa.Column("channel_id", sa.String(length=64), nullable=True))
        batch.alter_column("artwork_url", new_column_name="thumbnail_url")
        batch.alter_column("artist", new_column_name="channel_title")
