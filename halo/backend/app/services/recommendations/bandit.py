"""Thompson-sampling exploration over candidate sources.

Inspired by Spotify's BaRT ("Explore, Exploit, and Explain", McInerney et al., RecSys
2018): most slots go to the best-scored items (exploit), and a budget of slots goes to
items the ranker would not have picked (explore). Which *source* gets an exploration
slot is chosen by sampling each source's Beta(successes, failures) posterior, so sources
the listener responds to get explored more. Feedback updates the posterior.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

ARMS = ("search", "similar_artist", "co_listen", "listenbrainz")
EXPLORE_SHARE = {"familiar": 0.10, "balanced": 0.20, "discovery": 0.35}
GLOBAL_WEIGHT = 0.1  # how much the population prior counts toward one listener's arm


@dataclass(slots=True)
class ArmPosterior:
    alpha: float = 1.0
    beta: float = 1.0

    def sample(self, rng: random.Random) -> float:
        return rng.betavariate(max(self.alpha, 1e-3), max(self.beta, 1e-3))

    @property
    def mean(self) -> float:
        return self.alpha / (self.alpha + self.beta)


def combine(user: tuple[float, float] | None, global_: tuple[float, float] | None) -> ArmPosterior:
    """User evidence plus a down-weighted population prior. Both are stored with a (1, 1) prior."""
    alpha, beta = 1.0, 1.0
    if global_:
        alpha += GLOBAL_WEIGHT * (global_[0] - 1.0)
        beta += GLOBAL_WEIGHT * (global_[1] - 1.0)
    if user:
        alpha += user[0] - 1.0
        beta += user[1] - 1.0
    return ArmPosterior(alpha=max(alpha, 1.0), beta=max(beta, 1.0))


def explore_quota(discovery: str, expected_items: int) -> int:
    share = EXPLORE_SHARE.get(discovery, EXPLORE_SHARE["balanced"])
    return max(0, round(share * expected_items))


def choose_arm(
    posteriors: dict[str, ArmPosterior], available: set[str], rng: random.Random
) -> str | None:
    """Thompson sampling: draw from each available arm and pick the highest draw."""
    best_arm, best_draw = None, -1.0
    for arm in sorted(available):
        draw = posteriors.get(arm, ArmPosterior()).sample(rng)
        if draw > best_draw:
            best_arm, best_draw = arm, draw
    return best_arm


def reward(rating: str) -> bool | None:
    """Map feedback to a Bernoulli reward. None means 'no signal'."""
    if rating in ("like", "save"):
        return True
    if rating in ("dislike", "skip"):
        return False
    return None
