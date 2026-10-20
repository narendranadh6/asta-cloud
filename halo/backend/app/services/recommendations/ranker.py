"""Learnable ranking layer.

Stage two of the two-stage design described for YouTube ("Deep Neural Networks for
YouTube Recommendations", Covington et al., RecSys 2016): candidate generation casts a
wide net, then a ranker scores each candidate with richer features. Halo uses a small
logistic-regression model over interpretable features so it trains on Halo's own
(modest) feedback volume and stays explainable. Weights are retrained offline by
``python -m app.tasks.train_ranker`` and stored in ``model_artifacts``.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

FEATURES = (
    "relevance",  # heuristic match to the request (query rank, term overlap, intent)
    "cf_score",  # co-listening similarity to the listener's seeds (0..1)
    "similar_artist",  # 1 if found via a similar-artist expansion
    "co_listen",  # 1 if found via co-listening
    "listenbrainz",  # 1 if found via ListenBrainz artist radio (real listening data)
    "liked_channel",  # 1 if the listener liked/saved this channel before
    "popularity_z",  # log10(views) relative to the candidate set median
    "pop_x_discovery",  # popularity_z * (+1 familiar, 0 balanced, -1 discovery)
)

DEFAULT_WEIGHTS: dict[str, float] = {
    "relevance": 1.0,
    "cf_score": 0.8,
    "similar_artist": 0.05,
    "co_listen": 0.15,
    "listenbrainz": 0.12,
    "liked_channel": 0.15,
    "popularity_z": 0.0,
    "pop_x_discovery": 0.08,
}


@dataclass(slots=True)
class RankerModel:
    weights: dict[str, float] = field(default_factory=lambda: dict(DEFAULT_WEIGHTS))
    bias: float = 0.0
    trained_examples: int = 0

    def score(self, features: dict[str, float]) -> float:
        return self.bias + sum(
            self.weights.get(name, 0.0) * features.get(name, 0.0) for name in FEATURES
        )

    def probability(self, features: dict[str, float]) -> float:
        return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, self.score(features)))))

    def to_payload(self) -> dict[str, object]:
        return {"weights": self.weights, "bias": self.bias}

    @classmethod
    def from_payload(
        cls, payload: dict[str, object] | None, trained_examples: int = 0
    ) -> RankerModel:
        if not payload:
            return cls()
        raw = payload.get("weights", {})
        weights = dict(DEFAULT_WEIGHTS)
        if isinstance(raw, dict):
            for name in FEATURES:
                value = raw.get(name)
                if isinstance(value, int | float) and math.isfinite(value):
                    weights[name] = float(value)
        bias = payload.get("bias", 0.0)
        return cls(
            weights=weights,
            bias=float(bias) if isinstance(bias, int | float) else 0.0,
            trained_examples=trained_examples,
        )


def train(
    examples: list[tuple[dict[str, float], int]],
    *,
    epochs: int = 200,
    lr: float = 0.05,
    l2: float = 0.01,
    seed: int = 7,
    prior: RankerModel | None = None,
) -> RankerModel:
    """Logistic regression with SGD and L2 shrinkage toward the prior weights.

    Shrinking toward the hand-set defaults (not toward zero) keeps the ranker sensible
    while feedback is scarce.
    """
    prior = prior or RankerModel()
    model = RankerModel(weights=dict(prior.weights), bias=prior.bias)
    if not examples:
        return model
    rng = random.Random(seed)
    data = list(examples)
    for _ in range(epochs):
        rng.shuffle(data)
        for features, label in data:
            error = model.probability(features) - label
            model.bias -= lr * error
            for name in FEATURES:
                gradient = error * features.get(name, 0.0) + l2 * (
                    model.weights[name] - prior.weights[name]
                )
                model.weights[name] -= lr * gradient
    model.trained_examples = len(examples)
    return model
