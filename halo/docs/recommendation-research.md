# How the big services recommend music, and what Halo uses

Spotify, Apple Music and YouTube Music don't publish their recommendation code, and
decompiling or scraping their apps would break their terms. This document works from what
they **have** published: research papers, engineering blogs and open-source libraries on
GitHub. It then maps each technique to how Halo implements it with **its own data only**.

Research date: October 2026.

## YouTube / YouTube Music

**Sources**
* Covington, Adams & Sargin, *Deep Neural Networks for YouTube Recommendations*, RecSys 2016:
  [research.google/pubs/pub45530](https://research.google/pubs/pub45530)
* Zhao et al., *Recommending What Video to Watch Next: A Multitask Ranking System*, RecSys 2019:
  [research.google/pubs/pub49380](https://research.google/pubs/pub49380/) (DOI 10.1145/3298689.3346997)

**What they describe**
* **Two stages.** A *candidate generation* model narrows millions of videos to hundreds;
  a separate *ranking* model scores those with richer features.
* **Several objectives.** The 2019 "watch next" ranker optimises several goals at once
  (engagement and satisfaction) with Multi-gate Mixture-of-Experts. It corrects for
  position and selection bias with a Wide & Deep "shallow tower".
* The recommender relies on implicit feedback (what people actually watch) plus explicit
  signals.

**In Halo**
| Technique | Halo implementation |
|---|---|
| Candidate generation, then ranking | `pipeline.py` gathers candidates from three sources, then `rank_and_explore` ranks them |
| Learned ranking over features | `ranker.py`: logistic regression over interpretable features (relevance, co-listening score, source, liked channel, popularity × discovery level). Retrained by `app/tasks/train_ranker.py` from logged feedback |
| Watch next | `GET /api/v1/recommendations/next`, shown as "Up next — picked for you" on the Now in Brave screen |
| Bias awareness | Exploration slots (below) gather feedback on items the ranker would not have shown, which reduces the feedback-loop bias a pure ranker creates |

Halo does **not** train deep networks. It doesn't have YouTube-scale data, and a small
explainable model is the right fit for its feedback volume.

## Spotify

**Sources**
* McInerney, Lacker, Hansen, Higley, Bouchard, Gruson & Mehrotra, *Explore, Exploit, and
  Explain: Personalizing Explainable Recommendations with Bandits* ("BaRT"), RecSys 2018:
  [paper PDF](https://idea-stat.snu.ac.kr/seminar/20181207/Explore,%20exploit,%20and%20explain_%20personalizing%20explainable%20recommendations%20with%20bandits.pdf)
* Spotify Engineering, *Introducing Voyager: Spotify's New Nearest-Neighbor Search Library*
  (2023): [engineering.atspotify.com](https://engineering.atspotify.com/introducing-voyager-spotifys-new-nearest-neighbor-search-library).
  Open source on GitHub (`spotify/voyager`, successor to `spotify/annoy`)
* Spotify talk slides on recommending and searching, covering exploration and propensity
  scoring: [slideshare](https://www.slideshare.net/mounialalmas/recommending-and-searching-spotify)

**What they describe**
* **BaRT** treats Home-screen recommendations as a *multi-armed bandit*. Most of the time
  it shows what it predicts you'll like (*exploit*). Some of the time it shows something
  uncertain so it can learn (*explore*). Each recommendation comes with an *explanation*
  ("Because you listened to…").
* **Embeddings and nearest neighbours.** Tracks are mapped into a vector space. Tracks that
  appear together in many playlists end up close together. Annoy, and now Voyager (HNSW),
  find the nearest tracks quickly at scale.

**In Halo**
| Technique | Halo implementation |
|---|---|
| Explore / exploit with a bandit | `bandit.py`: a share of slots (10% familiar, 20% balanced, 35% discovery) goes to items the ranker would not pick. The source for each slot is chosen by **Thompson sampling** over Beta posteriors per listener, plus a down-weighted population prior |
| Explanations | Every pick carries reasons ("Listeners who saved X also saved this", "Similar to Y", "Something new for you") |
| Playlist co-occurrence | `repositories/recommendations.py::co_listened`: item-to-item co-occurrence across opted-in listeners' playlists, cosine-normalised. A pair needs at least two listeners, so no one's playlist can be read back |
| Feedback loop | Like/save and dislike/skip update the bandit arm that produced the item (`record_bandit_reward`) |

Halo computes co-occurrence directly in PostgreSQL, which is exact and fast at Halo's scale.
Past roughly a million playlist items, the upgrade path is item embeddings
(word2vec-style over playlists) indexed with Voyager.

## Apple Music

**Sources:** Apple publishes no research on the *For You* recommender. Public coverage
describes behaviour only: recommendations based on listening history, shaped by Love/Dislike
ratings, refreshed through the day, and an onboarding step that asks for genres and artists
to avoid a cold start. See
[9to5mac (2019)](https://9to5mac.com/2019/04/15/apple-music-for-you-upgrade/),
[Hypebot (2019)](https://www.hypebot.com/apple-music-expands-for-you-personalized-recommendations/)
and the [Microsoft HAX Toolkit case study](https://www.microsoft.com/en-us/haxtoolkit/?p=1511).
Anything more specific about Apple's models would be speculation, so this document doesn't
claim it.

**In Halo:** the same product patterns. Onboarding asks for languages, artists, genres and
moods (cold start). Explicit like/dislike feedback steers results. Taste Intelligence shows
and lets you correct what Halo has inferred.

## Open music APIs

| API | What it gives | Key | Used by Halo | Notes |
|---|---|---|---|---|
| [YouTube Data API v3](https://developers.google.com/youtube/v3) | Search, video metadata, most-popular chart | Yes (free quota) | **Yes**: all songs | Playback via handoff only |
| [Radio Browser](https://www.radio-browser.info/) | 50,000+ live radio stations with stream URLs, tags, language, country | No | **Yes**: Live Radio | Public-domain data, community run; send a User-Agent |
| [Last.fm API](https://www.last.fm/api) | `artist.getSimilar`, `track.getSimilar`, tags | Yes (free) | **Yes**: similar artists | Optional (`HALO_LASTFM_API_KEY`) |
| [Deezer API](https://developers.deezer.com/api) | Search, related artists, charts, 30 s previews | No | **Yes**: related artists fallback | No key needed |
| [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) | Open music encyclopedia: artists, recordings, tags | No | Not yet | 1 request/second; good for metadata cleanup |
| [ListenBrainz](https://listenbrainz.readthedocs.io/) | Open listening data, similar artists/recordings | Token for writes | Not yet | Open-data CF signals |
| [iTunes Search API](https://performance-partners.apple.com/search-api) | Catalog search, artwork, 30 s previews | No | Not yet | Previews must link back to Apple Music |
| [Audius API](https://docs.audius.org/) | Full tracks uploaded by artists, trending | App name | Not yet | Candidate for licensed native playback |
| [Jamendo API](https://developer.jamendo.com/v3.0) | Creative Commons full tracks | Client id | Not yet | Candidate for licensed native playback |

**Network note:** the development sandbox for this project could only reach Google's API.
The Last.fm, Deezer and Radio Browser adapters are covered by tests against recorded
response shapes. They work once the server can reach those hosts, which normal hosting
allows.

## Privacy rules Halo keeps

* Personalization is off until the listener turns it on. Without consent nothing is logged
  for bandits, the ranker or co-listening.
* Co-listening only uses playlists of listeners who opted in, with a two-listener minimum
  per pair.
* Only artist names are sent to Last.fm or Deezer, never user identifiers.
