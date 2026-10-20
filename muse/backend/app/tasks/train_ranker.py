"""Retrain the ranking model from logged recommendation feedback.

    python -m app.tasks.train_ranker

Run daily or weekly. Needs feedback from listeners who enabled personalization.
"""

from __future__ import annotations

import asyncio
import logging

from app.repositories import recommendations as rec_repo
from app.services.recommendations.ranker import train

logger = logging.getLogger("muse.tasks.train_ranker")
MIN_EXAMPLES = 50


async def _main() -> None:
    from app.core.config import get_settings
    from app.db.session import create_engine, create_session_factory

    engine = create_engine(get_settings().database_url)
    try:
        async with create_session_factory(engine)() as session:
            examples = await rec_repo.training_examples(session)
            if len(examples) < MIN_EXAMPLES:
                logger.info("only %d examples; keeping current ranker", len(examples))
                return
            prior = await rec_repo.load_ranker(session)
            model = train(examples, prior=prior)
            await rec_repo.save_ranker(session, model)
            await session.commit()
            logger.info("trained ranker on %d examples: %s", len(examples), model.weights)
    finally:
        await engine.dispose()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(_main())
