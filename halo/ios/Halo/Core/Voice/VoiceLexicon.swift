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
        "uh", "um", "umm", "uhh", "hmm", "er", "beats", "numbers",
        "పెట్టు", "పెట్టండి", "చెయ్యి", "చేయి", "వినిపించు", "కావాలి", "ఏమైనా", "ఏదైనా", "కొంచెం",
        "ఒక", "లో", "కి", "మంచి", "పాటలు", "పాట", "చేద్దాం",
    ]

    // MARK: Transport

    static let next = ["skip", "next song", "next", "skip cheyyi", "tarvata", "tharvatha",
                       "తర్వాత", "తర్వాతది", "next పెట్టు"]
    static let previous = ["previous", "go back", "last song", "previous song", "back", "song before",
                           "the one before", "previous one", "venakki", "వెనక్కి", "ముందు song", "mundu song",
                           "mundu paata", "mundu pata", "ముందు పాట"]
    static let restart = ["restart", "from the start", "from the beginning", "start over", "from the top",
                          "malli start", "modati nunchi", "modatinunchi", "మొదటి నుంచి"]
    static let pause = ["pause", "stop", "aapu", "aapey", "ఆపు", "ఆపేయ్", "ఆపండి"]
    static let resume = ["resume", "continue", "keep playing", "కొనసాగించు"]
    static let removeNext = ["remove the next", "remove next", "skip the next", "dont play the next",
                             "take the next", "remove the upcoming", "next song remove",
                             "next vachche song remove", "next పాట తీసేయ్"]

    // MARK: Vibe

    static let energyUp = ["energetic", "energy", "upbeat", "pump", "pumped", "party", "dance",
                           "workout", "gym", "fast", "faster", "wake me up", "hype", "high energy",
                           "josh", "జోష్", "mass", "మాస్", "beat", "loud", "ఎనర్జీ", "జిమ్", "డాన్స్",
                           "husharu", "hushaaru", "హుషార", "ఉత్సాహ", "utsaham", "జోరు", "lively"]
    static let energyDown = ["calm", "calmer", "relax", "relaxing", "peaceful", "slow", "slower",
                             "chill", "soft", "softer", "soothing", "sleep", "sleepy", "quiet",
                             "mellow", "melody", "melodies", "prashanthamga", "nemmadiga", "prashantham",
                             "prashanthamaina", "nemmadi", "nemmadaina", "melodious", "gentle", "నెమ్మద",
                             "ప్రశాంత", "నెమ్మది", "మెలోడీ", "స్లో", "మెల్లగా", "శాంత"]
    static let happy = ["happy", "happier", "cheerful", "feel good", "feelgood", "bright", "joyful",
                        "santhosham", "santhoshamga", "anandam", "సంతోష", "ఆనంద", "హ్యాపీ"]
    static let sad = ["sad", "emotional", "heartbreak", "melancholic", "melancholy", "depressing",
                      "gloomy", "sorrowful", "crying", "badha", "baadha", "vishadam", "vishada",
                      "బాధ", "విషాద", "దుఃఖ"]
    /// "Fast beat unna songs": a quick tempo (and energy).
    static let tempoFast = ["fast beat", "fast beats", "fast tempo", "beat unna", "beats unna", "rhythmic",
                            "uptempo", "up tempo", "high tempo", "beat heavy", "beat ekkuva", "vegamga", "vegamaina",
                            "ఫాస్ట్ బీట్", "బీట్ ఉన్న", "బీట్ ఎక్కువ", "వేగ"]
    static let tempoSlow = ["slow tempo", "slow beat", "low tempo"]
    static let romantic = ["romantic", "love songs", "prema", "ప్రేమ", "రొమాంటిక్"]
    /// "more X", "-er", "ఎక్కువ", "పెంచు": change relative to now instead of setting a value.
    static let more = ["more", "ekkuva", "ఎక్కువ", "penchu", "పెంచు", "increase", "make it"]
    static let less = ["less", "takkuva", "తక్కువ", "thaggi", "తగ్గించు", "reduce"]
    /// "a bit", "slightly": a smaller step.
    static let slightly = ["slightly", "a bit", "a little", "little", "konchem", "కొంచెం"]

    // MARK: Time

    static let newerWords = ["newer", "kothavi", "kottavi", "కొత్తవి"]
    static let newWords = ["new", "latest", "fresh", "లేటెస్ట్", "recent", "recently", "kotha",
                           "kottha", "కొత్త", "this week", "yesterday", "ninna", "నిన్న",
                           "release aina", "released", "విడుదల", "ee week", "ee month", "ee year", "ee nela", "ee vaaram",
                           "ee samvatsaram",
                           "ఈ వారం", "ఈ నెల", "ఈ సంవత్సరం",
                           "this month", "this year", "yesterday", "last few months", "just released"]
    static let olderWords = ["older", "paathavi", "pathavi", "పాతవి"]
    /// Decades said as words ("nineties", "తొంభైల").
    static let decadeWords: [(Int, [String])] = [
        (1970, ["seventies", "debbhai", "డెబ్బై"]),
        (1980, ["eighties", "enabhai", "ఎనభై"]),
        (1990, ["nineties", "tombhai", "thombhai", "తొంభై"]),
        (2000, ["two thousands", "2000s"]),
    ]
    static let oldWords = ["old", "classic", "classics", "old hits", "evergreen", "retro", "purana", "puraana",
                           "vintage", "paatha", "patha", "పాత"]

    // MARK: Discovery and direction

    static let discovery = ["something new", "new to me", "never heard", "havent heard",
                            "discover", "discovery", "explore", "something i dont know",
                            "teliyani", "teliyanivi", "vinani", "తెలియని", "వినని", "never listened"]
    static let familiar = ["familiar", "songs i know", "my favorites", "my favourites", "known songs",
                           "already know", "telisina", "telisinavi", "తెలిసిన"]
    static let surprise = ["surprise me", "surprise"]
    /// "Anything" means "surprise me" only when nothing else was asked for.
    static let anything = ["anything", "random", "ఏదైనా", "edaina", "emaina", "ఏమైనా"]
    static let similar = ["more like this", "like this", "similar", "same kind", "ilaanti",
                          "ilanti", "ఇలాంటి", "ఇలాంటివి"]
    static let lockVibe = ["keep this vibe", "keep the vibe", "keep it like this", "keep this mood",
                           "maintain", "perfect", "ide vibe", "ఇదే vibe", "ఇదే", "ilage unchu",
                           "alage unchu", "ilaage unchu", "ఇలాగే", "ఇలానే", "lock cheyyi", "lock this",
                           "vibe lock", "mood lock", "ee mood ne", "ee vibe ne"]
    static let same = ["same vibe", "same mood", "same feel", "same energy", "అదే vibe", "ade vibe",
                       "ade mood", "అదే మూడ్", "అదే", "same"]
    /// "Vere songs": other songs, not another vibe.
    static let otherSongs = ["vere songs", "vere paatalu", "vere patalu", "other songs", "different songs",
                             "వేరే పాటలు", "వేరే songs", "new set"]
    static let elsewhere = ["somewhere different", "something different", "change the vibe",
                            "change vibe", "different vibe", "mood change", "take me somewhere",
                            "vere vibe", "వేరే vibe", "వేరే"]
    static let deeper = ["go deeper", "deeper", "deep cuts", "lotuga", "lotu ga", "లోతుగా"]

    // MARK: Ratings

    static let neverAgain = ["dont recommend this again", "dont recommend again", "never play this",
                             "never again", "dont play this again", "malli pettaku", "మళ్ళీ పెట్టకు",
                             "ఇంకెప్పుడూ పెట్టకు"]
    static let later = ["again later", "save for later", "save this for later", "for later", "later"]
    static let like = ["i like this", "i love this", "love this", "add to favorites",
                       "add to favourites", "add this to my favorites", "add this to my favourites",
                       "favorite", "favourite", "save this", "nachindi", "నచ్చింది",
                       "remember that i like", "save cheyyi", "save chey", "సేవ్ చెయ్యి", "save చెయ్యి"]
    static let dislike = ["i dont like this", "dont like this", "dont like", "nachaledu", "నచ్చలేదు",
                          "less like this", "bad song"]
    static let keep = ["keep this one", "this is good", "this one is good", "good one", "nice",
                       "bagundi", "బాగుంది", "super", "awesome", "yeah this is good", "keep it", "not bad",
                       "bagane", "baagane", "బాగానే", "idi bagundi"]

    // MARK: Questions

    static let whoIsSinging = ["who is singing", "whos singing", "who sings", "who sang",
                               "who is this", "singer evaru", "evaru padaru", "evaru paadaru",
                               "paadindi evaru", "who is the singer", "whos the singer",
                               "ఎవరు పాడారు", "ఎవరు పాడింది", "singer ఎవరు", "పాడింది ఎవరు"]
    static let whatMovie = ["what movie", "which movie", "what film", "which film", "ఏ movie",
                            "ye movie", "ఏ సినిమా", "e cinema"]
    static let whatAlbum = ["what album", "which album", "e album", "ఏ ఆల్బమ్", "ఏ album", "album lodi",
                            "ఆల్బమ్ లోది"]
    static let whenReleased = ["when was this released", "when released", "release date",
                               "eppudu release", "ఎప్పుడు release", "when did this", "when did it come out",
                               "eppudu vachindi", "ఎప్పుడు విడుదల", "ఎప్పుడు వచ్చింది", "release ayindi"]
    /// "Came out" asks about release only with a question word ("put on what came out
    /// yesterday" is a request).
    static let cameOut = ["come out", "came out", "విడుదలైంది"]
    static let upNext = ["whats next", "what is next", "whats coming next", "what is coming next",
                         "next enti", "next ఏంటి", "coming up", "which song is next", "what plays next",
                         "next e song", "next ఏ పాట", "tarvata e paata", "tarvata ఏ పాట",
                         "తర్వాత ఏ పాట"]
    static let undo = ["undo", "cancel that", "undo that", "wait no", "go back to before", "the way it was",
                       "how it was", "revert", "take that back", "reverse that", "mundu laaga", "mundu laage",
                       "mundu unnatte", "antaku mundu", "paatha settings", "previous settings", "అంతకు ముందు",
                       "ముందు లాగా", "ముందు ఉన్నట్టే", "మార్పు రద్దు"]

    // MARK: Artists

    static let thisArtist = ["this singer", "this artist", "that singer", "that artist", "ee singer",
                             "ee artist", "ee gayakudu", "ee gayani", "ఈ singer", "ఈ artist", "ఈ సింగర్",
                             "ఈ గాయకుడు", "ఈ గాయకుడి", "ఈ గాయని", "ఈ ఆర్టిస్ట్", "ee music director"]
    /// The song that is playing ("ee song vaddu", "not this song").
    static let thisSong = ["this song", "this one", "this track", "that song", "ee song", "ee paata", "ee pata",
                           "ee track", "ఈ పాట", "ఈ song"]
    /// "Never" for artists and songs: a lasting (profile) change, confirmed when unsure.
    static let never = ["never", "ever again", "inkeppudu", "ఇంకెప్పుడూ", "forever"]
    /// "Not too much" with no name: the artist named last.
    static let lessOfThem = ["not too much", "too much", "not too many", "too many", "less of them", "not so much",
                             "not so many", "takkuva pettu", "తక్కువ పెట్టు",
                             "not so often", "fewer", "takkuva cheyyi", "తక్కువ చెయ్యి", "konchem takkuva",
                             "ekkuva vaddu", "ekkuva pettaku", "ఎక్కువ వద్దు", "ఎక్కువ పెట్టకు"]
    /// "Released", "came out": about time, never names.
    static let releaseWords = ["vachina", "vachinavi", "vachchina", "vachindi", "vastundi", "vache", "vachche",
                               "aina", "ayina", "released", "విడుదలైన", "విడుదలైంది", "వచ్చిన", "వచ్చింది", "వస్తుంది"]
    /// "I don't mind …", "… aina parledu", "… are fine": accepting a mood, not asking to play.
    static let acceptances = ["dont mind", "wouldnt mind", "would not mind", "do not mind", "aina parledu",
                              "aina okay", "ayina parledu", "are fine", "is fine", "fine too", "okay too", "ok too",
                              "no problem", "parledu", "పర్లేదు", "అయినా పర్లేదు"]
    /// "Only Telugu", "from now on": a rule for the session, not a request to start.
    static let restrictions = ["only", "matrame", "మాత్రమే", "from now on", "ika nunchi", "ఇక నుంచి"]
    /// "Prefer Telugu", "give English priority": lean towards a language without "only".
    static let preferWords = ["prefer", "priority", "lean towards", "lean toward", "favour", "favor"]
    /// Hesitations that can surround a request without being part of it.
    static let hesitations: Set<String> = ["adi", "ante", "aa", "umm", "um", "uh", "hmm", "er", "అది", "అంటే", "ఆ",
                                           "ఏం", "like", "that"]
    /// "I forgot the name": the thing to play is missing.
    static let forgotName = ["gurthu ledu", "gurtu ledu", "forgot the name", "dont remember the name",
                             "what was the name", "peru enti", "గుర్తు లేదు", "ఏంటి పేరు", "పేరు ఏంటి"]
    /// "Switch the language" with no language named.
    static let languageChange = ["change the language", "change language", "language marchu", "language maarchu",
                                 "language ni marchu", "language ni change", "bhasha marchu", "bhasha maarchu",
                                 "bhasha ni maarchu", "భాష మార్చు", "భాష మార్చండి", "భాషని మార్చు", "switch the language"]

    /// Words that start like a command word but mean something else ("news" isn't "new").
    static let falsePrefixes: Set<String> = ["news", "newspaper", "newsletter", "classical", "classically",
                                             "massive", "massively", "massage", "nextdoor", "stopwatch",
                                             "playstation", "playground", "sadly", "nowhere"]
    /// Words that say "I want to hear …" without a play verb.
    static let requestCues = ["hear", "listen", "feel like", "in the mood for", "some", "songs", "music",
                              "paatalu", "patalu", "sangeetham", "సంగీతం", "పాటలు", "kavali", "కావాలి", "vinali"]
    /// Question words; with a "next" word they ask what's coming, never skip.
    static let questionWords = ["what", "whats", "which", "emi", "enti", "e", "ఏమి", "ఏ", "ఏంటి", "ఏది"]
    static let nextWords = ["next", "after this", "coming up", "tarvata", "తర్వాత"]
    static let differentArtist = ["different singer", "different artist", "another singer",
                                  "another artist", "someone else", "vere singer", "వేరే singer",
                                  "వేరే artist"]
    static let refuse = ["vaddu", "వద్దు", "వద్దులే", "pettaku", "pettakandi", "పెట్టకు", "పెట్టకండి",
                         "vaddandi", "vaddhu", "oddu", "వద్దండి"]

    // MARK: Negation (see `Utterance.isNegated`)

    /// Whole words that negate a request.
    static let negationWords: Set<String> = ["dont", "never", "not", "no", "without", "avoid", "away", "nothing",
                                             "neither", "nor", "vaddu", "vaddandi", "vaddhu", "oddu", "asalu",
                                             "chalu", "chaalu", "చాలు"]
    /// Phrases that negate a request.
    static let negationPhrases = ["do not", "no more", "enough of", "stop playing", "dont want", "dont you dare",
                                  "i dont want", "keep away", "వద్దు", "వద్దండి", "పెట్టకు", "పెట్టకండి",
                                  "వినిపించకు", "వినిపించకండి", "చేయకు", "చెయ్యకు", "ఆపకు", "మార్చకు", "వేయకు"]
    /// Look negative, aren't: "I don't mind sad songs", "no problem", "sad songs parledu".
    static let notNegations = ["dont mind", "do not mind", "dont care", "no problem", "no worries", "not bad",
                               "never mind", "parledu", "పర్లేదు", "no issue"]
    /// Romanized words ending like a negative imperative that aren't one ("naaku" = to me).
    static let notNegativeImperatives: Set<String> = ["naaku", "maaku", "meeku", "vaaku", "thaaku", "baaku"]
    static let today = ["today", "ivala", "ఈరోజు", "ఇవాళ"]

    // MARK: Outside music, nothing to do

    /// Requests Halo doesn't handle. With no music in the sentence they are "unsupported", and
    /// never fall back to a player action.
    static let offDomain = [
        "call", "phone", "dial", "message", "whatsapp", "sms", "text him", "text her", "email", "mail",
        "alarm", "timer", "remind", "reminder", "weather", "temperature", "forecast", "navigate",
        "navigation", "directions", "route", "map", "maps", "traffic", "open", "launch", "news",
        "lyrics", "buy", "order", "pay", "payment", "recharge", "uber", "camera", "selfie", "flashlight",
        "కాల్", "ఫోన్", "అలారం", "వాతావరణం", "దారి", "మ్యాప్", "మెసేజ్", "లిరిక్స్", "వార్తలు", "vatavaranam",
    ]
    /// Filler and hesitation only.
    static let noise: Set<String> = ["uh", "um", "umm", "uhh", "hmm", "hm", "ah", "aa", "aah", "er", "eh",
                                     "ok", "okay", "హా", "ఆ", "అ", "ఏం", "అయ్యో", "ayyo", "adi", "అది", "wait"]
    static let neverMind = ["never mind", "nevermind", "nothing", "forget it", "leave it", "its fine",
                            "vaddule", "vaddu le", "em ledu", "emi ledu", "emledu", "ఏమీ లేదు",
                            "వద్దులే", "parledu", "పర్లేదు"]
    /// "Don't skip", "aapakandi": a control word that is negated means nothing should happen.
    static let controlNegation = ["dont", "do not", "cheyyaku", "cheyakandi", "cheyyakandi", "aapaku",
                                  "aapakandi", "ఆపకు", "ఆపకండి", "చేయకు", "చెయ్యకు", "చేయకండి"]
    static let controlWords = ["skip", "next", "stop", "pause", "aapu", "ఆప", "change", "తర్వాత"]

    // MARK: Genres (played as a genre, never treated as a name)

    static let genres: [(String, [String])] = [
        ("jazz", ["jazz"]), ("rock", ["rock"]), ("pop", ["pop"]), ("hip hop", ["hip hop", "hiphop", "rap"]),
        ("classical", ["classical", "శాస్త్రీయ"]), ("carnatic", ["carnatic", "కర్ణాటక"]), ("folk", ["folk", "జానపద"]),
        ("devotional", ["devotional", "bhakti", "భక్తి"]), ("edm", ["edm"]), ("lofi", ["lofi", "lo fi"]),
        ("indie", ["indie"]), ("metal", ["metal"]), ("ghazal", ["ghazal"]), ("sufi", ["sufi"]),
        ("bhajan", ["bhajan", "భజన"]), ("instrumental", ["instrumental"]),
    ]

    /// Everyday words that are never names on their own: if a captured "name" is only these,
    /// nothing is captured. Keeps "for the drive" or "lately" from becoming an artist.
    static let commonWords: Set<String> = [
        "about", "after", "again", "all", "already", "also", "am", "any", "as", "at", "back", "be",
        "because", "been", "before", "both", "by", "car", "could", "day", "did", "do", "does", "down",
        "drive", "driving", "during", "each", "ever", "every", "evening", "get", "go", "going", "good",
        "got", "had", "has", "have", "he", "her", "here", "him", "his", "home", "how", "if", "im", "in",
        "into", "ive", "its", "journey", "kind", "lately", "lot", "lots", "many", "may", "maybe", "mine",
        "morning", "most", "my", "night", "nice", "off", "office", "often", "one", "ones", "only", "our",
        "out", "over", "own", "put", "right", "ride", "road", "she", "should", "still", "such", "than",
        "their", "them", "then", "there", "these", "they", "thing", "things", "those", "through", "time",
        "travel", "trip", "under", "until", "up", "us", "was", "way", "we", "well", "were", "what",
        "when", "where", "which", "while", "who", "why", "work", "would", "yeah", "yes", "your",
        "releases", "release", "listen", "hear", "heard", "listening", "playing", "played", "bro", "dude",
        "kuda", "ayipoyindi", "ayyindi", "unnayi", "undi", "chesi", "ante", "mari", "tho", "nu", "vi",
        "konni", "chala", "baga", "ippudu", "ikkada", "akkada", "maaku", "meeru", "cheppu", "chudu",
        "vinu", "kosam", "lekunda", "anni", "inkaa", "malli", "evi", "edi", "emaina",
        "కూడా", "అయిపోయింది", "ఇప్పుడు", "చాలా", "బాగా", "కోసం", "అన్ని", "ఉన్నాయి", "ఉంది",
        "ఉండే", "ఉన్న", "గా", "వచ్చిన", "though", "tho", "ra", "raa", "yaar", "yar", "asalu", "assalu", "gaari",
        "garu", "gaaru", "andi", "kaani", "anyway", "pls", "unna", "unnavi", "అసలు", "గారి", "గారు",
        "vaalla", "vaallavi", "valla", "their", "them", "those", "వాళ్ళ", "వాళ్ళవి", "kaadu", "కాదు", "nah",
        "chalu", "chaalu", "top", "best", "hit", "popular", "great", "nela", "నెల", "again", "one",
    ]

    /// Telugu attaches suffixes ("ప్రశాంతమైన", "తొంభైల"), so a Telugu-script word counts as known
    /// when it contains a known Telugu stem of three or more letters.
    static func isKnown(_ word: String) -> Bool {
        if knownWords.contains(word) { return true }
        guard word.unicodeScalars.contains(where: { (0x0C00...0x0C7F).contains($0.value) }) else {
            // Romanized Telugu suffixes on a known word: "hushaaruga", "telugulo", "melodylo".
            for suffix in ["gaa", "ga", "lo", "ki", "ni", "nu", "tho", "vi", "la", "aina", "ina"]
            where word.hasSuffix(suffix) && word.count - suffix.count >= 4 {
                if knownWords.contains(String(word.dropLast(suffix.count))) { return true }
            }
            return false
        }
        return teluguStems.contains { teluguContains(word, $0) }
    }

    /// Substring search on Unicode scalars. Swift compares Telugu by grapheme cluster, so the
    /// stem "హుషార" isn't "in" "హుషారైన" (ర and ై form one cluster); scalars find it.
    static func teluguContains(_ text: String, _ part: String) -> Bool {
        let haystack = Array(text.unicodeScalars), needle = Array(part.unicodeScalars)
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    static let teluguStems: [String] = knownWords.filter { word in
        word.unicodeScalars.count >= 3 && word.unicodeScalars.allSatisfy { (0x0C00...0x0C7F).contains($0.value) }
    }.sorted()

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
            discovery, familiar, surprise, anything, similar, lockVibe, same, elsewhere, deeper, neverAgain,
            later, like, dislike, keep, whoIsSinging, whatMovie, whatAlbum, whenReleased, upNext,
            undo, thisArtist, differentArtist, refuse, today, onlyWords, mixWords, alternateWords,
            mostlyWords, someWords, languages.flatMap(\.1), tempoFast, tempoSlow, otherSongs, thisSong,
            never, lessOfThem, neverMind, controlNegation, releaseWords, requestCues, questionWords, nextWords,
            acceptances, restrictions, languageChange, preferWords, cameOut, forgotName, Array(hesitations), genres.flatMap(\.1), decadeWords.flatMap(\.1),
            Array(noise),
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
