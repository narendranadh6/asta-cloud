import Foundation

/// Words and phrases Halo understands, per concept, in every supported speech form:
/// English, romanized Telugu and Telugu script. Adding a language means adding entries here
/// (and tests), not changing the parser or the recommender.
///
/// Matching rules (see `Utterance.has`): Latin phrases match at the start of a word, so
/// "telugu" also matches "telugulo"; Telugu-script phrases match anywhere, because Telugu
/// attaches suffixes ("తెలుగులో").
enum VoiceLexicon {
    // MARK: Wake words and filler (ignored when looking for names)

    static let wake = ["hey halo", "ok halo", "okay halo", "halo", "హలో"]

    static let filler: Set<String> = [
        "play", "plays", "put", "give", "me", "some", "any", "a", "an", "the", "few", "of", "to",
        "for", "please", "plz", "now", "just", "can", "you", "i", "want", "need", "let", "lets",
        "start", "on", "with", "and", "but", "or", "it", "make", "is", "are", "be", "this", "that",
        "songs", "song", "music", "tracks", "track", "playlist", "mix", "stuff", "something",
        "pettu", "pettandi", "cheyyi", "chey", "cheyandi", "vinipinchu", "kavali", "kaavali",
        "emaina", "edaina", "konchem", "oka", "lo", "ki", "ni", "manchi", "try", "chedham",
        "paatalu", "patalu", "paata", "pata", "ok", "okay", "so", "too", "much", "really", "very",
        "పెట్టు", "పెట్టండి", "చెయ్యి", "చేయి", "వినిపించు", "కావాలి", "ఏమైనా", "ఏదైనా", "కొంచెం",
        "ఒక", "లో", "కి", "మంచి", "పాటలు", "పాట", "చేద్దాం",
    ]

    // MARK: Transport

    static let next = ["skip", "next song", "next", "skip cheyyi", "tarvata", "tharvatha",
                       "తర్వాత", "తర్వాతది", "next పెట్టు"]
    static let previous = ["previous", "go back", "last song", "previous song", "back",
                           "venakki", "వెనక్కి", "ముందు song", "mundu song"]
    static let restart = ["restart", "from the start", "from the beginning", "start over",
                          "malli start", "మొదటి నుంచి"]
    static let pause = ["pause", "stop", "aapu", "aapey", "ఆపు", "ఆపేయ్", "ఆపండి"]
    static let resume = ["resume", "continue", "keep playing", "కొనసాగించు"]
    static let removeNext = ["remove the next", "remove next", "skip the next", "dont play the next"]

    // MARK: Vibe

    static let energyUp = ["energetic", "energy", "upbeat", "pump", "pumped", "party", "dance",
                           "workout", "gym", "fast", "faster", "wake me up", "hype", "high energy",
                           "josh", "జోష్", "mass", "మాస్", "beat", "loud", "ఎనర్జీ", "జిమ్", "డాన్స్"]
    static let energyDown = ["calm", "calmer", "relax", "relaxing", "peaceful", "slow", "slower",
                             "chill", "soft", "softer", "soothing", "sleep", "sleepy", "quiet",
                             "mellow", "melody", "melodies", "prashanthamga", "nemmadiga",
                             "ప్రశాంతం", "నెమ్మది", "మెలోడీ", "స్లో"]
    static let happy = ["happy", "happier", "cheerful", "feel good", "feelgood", "bright",
                        "santhosham", "సంతోషం", "హ్యాపీ"]
    static let sad = ["sad", "emotional", "heartbreak", "melancholic", "badha", "బాధ"]
    static let romantic = ["romantic", "love songs", "prema", "ప్రేమ", "రొమాంటిక్"]
    /// "more X", "-er", "ఎక్కువ", "పెంచు": change relative to now instead of setting a value.
    static let more = ["more", "ekkuva", "ఎక్కువ", "penchu", "పెంచు", "increase", "make it"]
    static let less = ["less", "takkuva", "తక్కువ", "thaggi", "తగ్గించు", "reduce"]
    /// "a bit", "slightly": a smaller step.
    static let slightly = ["slightly", "a bit", "a little", "little", "konchem", "కొంచెం"]

    // MARK: Time

    static let newerWords = ["newer", "latest", "kothavi", "kottavi", "కొత్తవి", "లేటెస్ట్", "fresh"]
    static let newWords = ["new", "recent", "recently", "kotha", "kottha", "కొత్త", "this week",
                           "this month", "this year", "yesterday", "last few months", "just released"]
    static let olderWords = ["older", "paathavi", "pathavi", "పాతవి"]
    static let oldWords = ["old", "classic", "classics", "old hits", "evergreen", "retro",
                           "vintage", "paatha", "patha", "పాత"]

    // MARK: Discovery and direction

    static let discovery = ["something new", "new to me", "never heard", "havent heard",
                            "discover", "discovery", "explore", "something i dont know"]
    static let familiar = ["familiar", "songs i know", "my favorites", "my favourites", "known songs",
                           "తెలిసిన"]
    static let surprise = ["surprise me", "surprise", "anything", "random", "ఏదైనా"]
    static let similar = ["more like this", "like this", "similar", "same kind", "ilaanti",
                          "ilanti", "ఇలాంటి", "ఇలాంటివి"]
    static let lockVibe = ["keep this vibe", "keep the vibe", "keep it like this", "keep this mood",
                           "maintain", "perfect", "ide vibe", "ఇదే vibe", "ఇదే"]
    static let same = ["same vibe", "same mood", "same feel", "same energy", "అదే vibe", "ade vibe",
                       "same"]
    static let elsewhere = ["somewhere different", "something different", "change the vibe",
                            "change vibe", "different vibe", "mood change", "take me somewhere",
                            "vere vibe", "వేరే vibe", "వేరే"]
    static let deeper = ["go deeper", "deeper", "deep cuts"]

    // MARK: Ratings

    static let neverAgain = ["dont recommend this again", "dont recommend again", "never play this",
                             "never again", "dont play this again", "malli pettaku", "మళ్ళీ పెట్టకు",
                             "ఇంకెప్పుడూ పెట్టకు"]
    static let later = ["again later", "save for later", "save this for later", "for later", "later"]
    static let like = ["i like this", "i love this", "love this", "add to favorites",
                       "add to favourites", "add this to my favorites", "add this to my favourites",
                       "favorite", "favourite", "save this", "nachindi", "నచ్చింది",
                       "remember that i like"]
    static let dislike = ["i dont like this", "dont like this", "dont like", "nachaledu", "నచ్చలేదు",
                          "less like this", "bad song"]
    static let keep = ["keep this one", "this is good", "this one is good", "good one", "nice",
                       "bagundi", "బాగుంది", "super", "awesome", "yeah this is good"]

    // MARK: Questions

    static let whoIsSinging = ["who is singing", "whos singing", "who sings", "who sang",
                               "who is this", "singer evaru", "evaru padaru", "ఎవరు పాడారు",
                               "ఎవరు పాడింది", "singer ఎవరు"]
    static let whatMovie = ["what movie", "which movie", "what film", "which film", "ఏ movie",
                            "ye movie", "ఏ సినిమా", "e cinema"]
    static let whatAlbum = ["what album", "which album"]
    static let whenReleased = ["when was this released", "when released", "release date",
                               "eppudu release", "ఎప్పుడు release"]
    static let upNext = ["whats next", "what is next", "whats coming next", "what is coming next",
                         "next enti", "next ఏంటి"]
    static let undo = ["undo", "cancel that", "undo that", "wait no", "go back to before"]

    // MARK: Artists

    static let thisArtist = ["this singer", "this artist", "ee singer", "ee artist", "ఈ singer",
                             "ఈ artist", "ఈ సింగర్"]
    static let differentArtist = ["different singer", "different artist", "another singer",
                                  "another artist", "someone else", "vere singer", "వేరే singer",
                                  "వేరే artist"]
    static let refuse = ["vaddu", "వద్దు", "వద్దులే"]
    static let today = ["today", "ivala", "ఈరోజు", "ఇవాళ"]

    // MARK: Languages

    static let languages: [(MusicLanguage, [String])] = [
        (.telugu, ["telugu", "tollywood", "తెలుగు"]),
        (.english, ["english", "inglish", "hollywood", "ఇంగ్లీష్", "ఇంగ్లిష్"]),
        (.hindi, ["hindi", "bollywood", "హిందీ"]),
        (.tamil, ["tamil", "kollywood", "తమిళ"]),
        (.kannada, ["kannada", "sandalwood", "కన్నడ"]),
        (.malayalam, ["malayalam", "mollywood", "మలయాళ"]),
    ]
    static let onlyWords = ["only", "matrame", "మాత్రమే", "just"]
    static let mixWords = ["mix", "mixed", "both", "rendu", "రెండు"]
    static let alternateWords = ["alternate", "alternating", "one by one"]
    static let mostlyWords = ["mostly", "mainly", "ekkuva", "ఎక్కువ"]
    static let someWords = ["some", "a few", "few", "konni", "కొన్ని"]

    /// Every word the lexicon knows, so leftover words can be treated as names.
    static let knownWords: Set<String> = {
        var words = filler
        let lists: [[String]] = [
            wake, next, previous, restart, pause, resume, removeNext, energyUp, energyDown, happy,
            sad, romantic, more, less, slightly, newerWords, newWords, olderWords, oldWords,
            discovery, familiar, surprise, similar, lockVibe, same, elsewhere, deeper, neverAgain,
            later, like, dislike, keep, whoIsSinging, whatMovie, whatAlbum, whenReleased, upNext,
            undo, thisArtist, differentArtist, refuse, today, onlyWords, mixWords, alternateWords,
            mostlyWords, someWords, languages.flatMap(\.1),
            ["dont", "do", "not", "no", "without", "from", "movie", "cinema", "సినిమా", "album",
             "artist", "singer", "composer", "but", "actually", "instead", "back", "go", "it",
             "will", "would", "like", "vibe", "mood", "feel", "kind", "type", "style", "songs",
             "కానీ", "kani", "ga", "గా", "lo", "అయిన", "ayina", "release", "released", "unnaya",
             "ఉన్నాయా", "నాకు", "naaku", "nenu", "నేను", "ivvu", "ఇవ్వు", "ee", "ఈ", "ఆ", "aa",
             "months", "weeks", "days", "last", "week", "month", "year", "hits", "tracks"],
        ]
        for list in lists {
            for phrase in list {
                for word in phrase.split(separator: " ") { words.insert(String(word)) }
            }
        }
        return words
    }()
}
