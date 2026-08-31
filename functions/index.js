const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

if (!getApps().length) {
  initializeApp();
}

const tmdbReadToken = defineSecret("TMDB_READ_TOKEN");

const TMDB_API_BASE_URL = "https://api.themoviedb.org/3";
const TMDB_IMAGE_BASE_URL = "https://image.tmdb.org/t/p";
const MIN_FEATURE_RUNTIME_MINUTES = 60;
const SEARCH_RESULT_CANDIDATE_LIMIT = 12;
const TRAILER_PROVIDERS = {
  youtube: {
    site: "YouTube",
    keyPattern: /^[A-Za-z0-9_-]{6,32}$/,
    url: (key) => `https://www.youtube.com/watch?v=${key}`,
    embedUrl: (key) => `https://www.youtube.com/embed/${key}?rel=0`,
  },
  vimeo: {
    site: "Vimeo",
    keyPattern: /^\d{1,20}$/,
    url: (key) => `https://vimeo.com/${key}`,
    embedUrl: (key) => `https://player.vimeo.com/video/${key}?dnt=1`,
  },
  dailymotion: {
    site: "Dailymotion",
    keyPattern: /^[A-Za-z0-9_-]{4,128}$/,
    url: (key) => `https://www.dailymotion.com/video/${key}`,
    embedUrl: (key) => `https://www.dailymotion.com/embed/video/${key}`,
  },
};
const INVITE_CODE_PREFIX = "CINE";
const INVITE_CODE_LENGTH = 4;
const INVITE_CODE_SPACE = 10 ** INVITE_CODE_LENGTH;
const functionOptions = {
  region: "europe-west1",
  secrets: [tmdbReadToken],
  timeoutSeconds: 30,
  memory: "256MiB",
  maxInstances: 10,
  invoker: "public",
};
const authedFunctionOptions = {
  region: "europe-west1",
  timeoutSeconds: 30,
  memory: "256MiB",
  maxInstances: 10,
  invoker: "public",
};

exports.searchMovies = onRequest(
  functionOptions,
  async (request, response) => {
    if (!prepareRequest(request, response)) {
      return;
    }

    try {
      await verifyFirebaseAuth(request);

      const data = request.body?.data ?? request.body ?? {};
      const query = String(data?.query ?? "").trim();
      const language = sanitizeLocale(data?.language, "es-ES");
      const region = sanitizeRegion(data?.region, "ES");
      const page = sanitizePage(data?.page);

      if (query.length < 2) {
        sendError(
          response,
          400,
          "invalid-argument",
          "Search query must contain at least 2 characters.",
        );
        return;
      }

      const params = new URLSearchParams({
        query,
        language,
        region,
        page: String(page),
        include_adult: "false",
      });

      const result = await fetchTmdbMovies(
        "search/movie",
        params,
        page,
        true,
        SEARCH_RESULT_CANDIDATE_LIMIT,
      );
      response.json({result});
    } catch (error) {
      logger.error("Movie search failed", error);
      sendCaughtError(response, error);
    }
  },
);

exports.discoverMovies = onRequest(
  functionOptions,
  async (request, response) => {
    if (!prepareRequest(request, response)) {
      return;
    }

    try {
      await verifyFirebaseAuth(request);

      const data = request.body?.data ?? request.body ?? {};
      const language = sanitizeLocale(data?.language, "es-ES");
      const region = sanitizeRegion(data?.region, "ES");
      const page = sanitizePage(data?.page);
      const genreIds = sanitizeGenreIds(data?.genreIds);
      const yearStart = sanitizeYear(data?.yearStart);
      const yearEnd = sanitizeYear(data?.yearEnd);
      const minVoteAverage = sanitizeVoteAverage(data?.minVoteAverage);
      const countryCodes = sanitizeCountryCodes(data?.countryCodes);

      const params = new URLSearchParams({
        language,
        region,
        include_adult: "false",
        include_video: "false",
        "with_runtime.gte": String(MIN_FEATURE_RUNTIME_MINUTES),
        sort_by: sanitizeSortBy(data?.sortBy),
      });

      if (genreIds.length) {
        params.set("with_genres", genreIds.join("|"));
      }
      if (yearStart) {
        params.set("primary_release_date.gte", `${yearStart}-01-01`);
      }
      if (yearEnd) {
        params.set("primary_release_date.lte", `${yearEnd}-12-31`);
      }
      if (minVoteAverage) {
        params.set("vote_average.gte", String(minVoteAverage));
      }

      if (data?.random !== false) {
        const attempts = countryCodes.length ?
          shuffleValues(countryCodes).slice(0, Math.min(countryCodes.length, 8)) :
          [null];

        for (const countryCode of attempts) {
          if (countryCode) {
            params.set("with_origin_country", countryCode);
          } else {
            params.delete("with_origin_country");
          }

          params.set("page", "1");
          const first = await fetchTmdbMovies(
            "discover/movie",
            params,
            1,
            false,
          );
          if (first.totalResults === 0 && attempts.length > 1) {
            continue;
          }

          const maxPage = Math.max(1, Math.min(first.totalPages || 1, 500));
          const pageAttempts = Math.min(countryCodes.length ? 2 : 4, maxPage);
          const pages = shuffleValues(
            Array.from({length: maxPage}, (_, index) => index + 1),
          ).slice(0, pageAttempts);

          for (const randomPage of pages) {
            params.set("page", String(randomPage));
            const result = await fetchTmdbMovies(
              "discover/movie",
              params,
              randomPage,
            );
            if (result.results.length) {
              response.json({result});
              return;
            }
          }
        }

        response.json({result: {page: 1, totalPages: 0, totalResults: 0, results: []}});
        return;
      }

      if (countryCodes.length) {
        const countryCode = countryCodes[
          Math.floor(Math.random() * countryCodes.length)
        ];
        params.set("with_origin_country", countryCode);
      }
      params.set("page", String(page));
      const result = await fetchTmdbMovies("discover/movie", params, page);
      response.json({result});
    } catch (error) {
      logger.error("Movie discovery failed", error);
      sendCaughtError(response, error);
    }
  },
);

// Fetch a single, fully enriched movie when its ticket is opened. Discovery
// responses are intentionally batched and may be served from the client cache;
// this endpoint keeps optional data such as trailers fresh at the moment it is
// needed.
exports.getMovieDetails = onRequest(
  functionOptions,
  async (request, response) => {
    if (!prepareRequest(request, response)) {
      return;
    }

    try {
      await verifyFirebaseAuth(request);

      const data = request.body?.data ?? request.body ?? {};
      const tmdbId = Number(data?.tmdbId);
      const language = sanitizeLocale(data?.language, "es-ES");
      if (!Number.isFinite(tmdbId) || tmdbId <= 0) {
        sendError(response, 400, "invalid-argument", "Invalid TMDB movie id.");
        return;
      }

      const details = await fetchMovieDetails(tmdbId, language);
      if (isPornographicMovie(details, details) || isNonFeatureMovie(details, details)) {
        sendError(response, 404, "not-found", "Movie is not available.");
        return;
      }

      const movie = normalizeMovie(details, details);
      if (!isDisplayableMovie(movie)) {
        sendError(response, 404, "not-found", "Movie is not available.");
        return;
      }
      response.json({result: movie});
    } catch (error) {
      logger.error("Movie detail fetch failed", error);
      sendCaughtError(response, error);
    }
  },
);

exports.loadSocialState = onRequest(
  authedFunctionOptions,
  async (request, response) => {
    if (!prepareRequest(request, response)) {
      return;
    }

    try {
      const auth = await verifyFirebaseAuth(request);
      const result = await buildSocialState(auth.uid);
      response.json({result});
    } catch (error) {
      logger.error("Social state load failed", error);
      sendCaughtError(response, error);
    }
  },
);

exports.connectFriend = onRequest(
  authedFunctionOptions,
  async (request, response) => {
    if (!prepareRequest(request, response)) {
      return;
    }

    try {
      const auth = await verifyFirebaseAuth(request);
      const data = request.body?.data ?? request.body ?? {};
      const code = normalizeInviteCode(data?.code);

      if (!code) {
        sendError(
          response,
          400,
          "invalid-argument",
          "Introduce un código de invitación válido.",
        );
        return;
      }

      const db = getFirestore();
      await ensureUserInviteCode(auth.uid);
      const targetSnapshot = await db
        .collection("users")
        .where("friendCode", "==", code)
        .limit(2)
        .get();

      const targetDocs = targetSnapshot.docs
        .filter((document) => document.id !== auth.uid);

      if (!targetDocs.length) {
        sendError(
          response,
          404,
          "not-found",
          "No hemos encontrado a nadie con ese código.",
        );
        return;
      }

      const targetUid = targetDocs[0].id;
      const userFriendRef = db
        .collection("users")
        .doc(auth.uid)
        .collection("friends")
        .doc(targetUid);
      const targetFriendRef = db
        .collection("users")
        .doc(targetUid)
        .collection("friends")
        .doc(auth.uid);
      const alreadyConnected = (await userFriendRef.get()).exists;
      const serverTime = FieldValue.serverTimestamp();

      await db.runTransaction(async (transaction) => {
        transaction.set(userFriendRef, {
          friendUid: targetUid,
          status: "connected",
          createdAt: serverTime,
          updatedAt: serverTime,
        }, {merge: true});
        transaction.set(targetFriendRef, {
          friendUid: auth.uid,
          status: "connected",
          createdAt: serverTime,
          updatedAt: serverTime,
        }, {merge: true});
      });

      const result = await buildSocialState(auth.uid);
      response.json({
        result: {
          ...result,
          connectedFriendId: targetUid,
          alreadyConnected,
        },
      });
    } catch (error) {
      logger.error("Friend connection failed", error);
      sendCaughtError(response, error);
    }
  },
);

function prepareRequest(request, response) {
  if (request.method === "OPTIONS") {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    response.status(204).send("");
    return false;
  }

  response.set("Access-Control-Allow-Origin", "*");

  if (request.method !== "POST") {
    sendError(response, 405, "method-not-allowed", "Use POST.");
    return false;
  }

  return true;
}

async function buildSocialState(uid) {
  const db = getFirestore();
  const inviteCode = await ensureUserInviteCode(uid);
  const userRef = db.collection("users").doc(uid);
  const [currentWatchlistSnapshot, currentSeenSnapshot, friendsSnapshot] = await Promise.all([
    userRef.collection("movieDecisions").where("status", "==", "watchlist").get(),
    userRef.collection("movieDecisions").where("status", "==", "seen").get(),
    userRef.collection("friends").where("status", "==", "connected").get(),
  ]);
  const currentWatchlist = currentWatchlistFromSnapshot(currentWatchlistSnapshot);
  const currentSeenKeys = movieKeysFromSnapshot(currentSeenSnapshot);
  const friends = await Promise.all(
    friendsSnapshot.docs
      .slice(0, 50)
      .map((document) =>
        buildFriendSocialState(document, currentWatchlist, currentSeenKeys),
      ),
  );

  return {
    inviteCode,
    friends: friends.filter(Boolean),
  };
}

async function buildFriendSocialState(
  friendDocument,
  currentWatchlist,
  currentSeenKeys,
) {
  const db = getFirestore();
  const data = friendDocument.data() || {};
  const friendUid = String(data.friendUid || friendDocument.id || "").trim();

  if (!friendUid) {
    return null;
  }

  const [profileSnapshot, friendWatchlistSnapshot, friendSeenSnapshot] = await Promise.all([
    db.collection("users").doc(friendUid).get(),
    db
      .collection("users")
      .doc(friendUid)
      .collection("movieDecisions")
      .where("status", "==", "watchlist")
      .get(),
    db
      .collection("users")
      .doc(friendUid)
      .collection("movieDecisions")
      .where("status", "==", "seen")
      .get(),
  ]);
  const profile = profileSnapshot.data() || {};
  const friendKeys = new Set(
    friendWatchlistSnapshot.docs
      .map((document) => {
        const data = document.data() || {};
        const movie = sanitizeMoviePayload(data.movie, data.tmdbId);
        return movie ? movieKeyFromDecision(data) : null;
      })
      .filter(Boolean),
  );
  const matches = currentWatchlist
    .filter((item) => friendKeys.has(item.key));
  const friendSeenKeys = movieKeysFromSnapshot(friendSeenSnapshot);
  const sharedSeenCount = [...currentSeenKeys]
    .filter((key) => friendSeenKeys.has(key))
    .length;
  const name = displayNameForUser(friendUid, profile);

  return {
    id: friendUid,
    name,
    initials: initialsForName(name),
    relation: "Conectado",
    color: colorForUid(friendUid),
    sharedSeenCount,
    keys: matches.map((item) => item.key),
    movies: matches.map((item) => item.movie).filter(Boolean),
  };
}

function movieKeysFromSnapshot(snapshot) {
  return new Set(
    snapshot.docs
      .map((document) => movieKeyFromDecision(document.data() || {}))
      .filter(Boolean),
  );
}

function currentWatchlistFromSnapshot(snapshot) {
  return snapshot.docs
    .map((document) => {
      const data = document.data() || {};
      const key = movieKeyFromDecision(data);
      if (!key) {
        return null;
      }
      const movie = sanitizeMoviePayload(data.movie, data.tmdbId);
      if (!movie) {
        return null;
      }

      return {
        key,
        movie,
      };
    })
    .filter(Boolean);
}

function movieKeyFromDecision(data) {
  const tmdbId = Number(data?.tmdbId);
  return Number.isFinite(tmdbId) && tmdbId > 0 ? `tmdb:${tmdbId}` : null;
}

function sanitizeMoviePayload(movie, fallbackTmdbId) {
  if (!movie || typeof movie !== "object") {
    return null;
  }

  const tmdbId = Number(movie.tmdbId ?? fallbackTmdbId);
  if (!Number.isFinite(tmdbId) || tmdbId <= 0) {
    return null;
  }
  const trailer = sanitizeTrailerPayload(
    movie.trailer,
    movie.trailerKey,
    movie.trailerSite,
  );

  const payload = {
    tmdbId,
    title: stringOrEmpty(movie.title || movie.originalTitle),
    originalTitle: stringOrEmpty(movie.originalTitle),
    overview: stringOrEmpty(movie.overview),
    releaseDate: stringOrEmpty(movie.releaseDate),
    year: movie.year == null ? null : String(movie.year),
    posterPath: nullableString(movie.posterPath),
    posterUrl: nullableString(movie.posterUrl),
    backdropPath: nullableString(movie.backdropPath),
    backdropUrl: nullableString(movie.backdropUrl),
    voteAverage: finiteNumber(movie.voteAverage),
    voteCount: finiteNumber(movie.voteCount),
    popularity: finiteNumber(movie.popularity),
    originalLanguage: stringOrEmpty(movie.originalLanguage),
    genreIds: numberArray(movie.genreIds).slice(0, 12),
    genres: genreArray(movie.genres).slice(0, 12),
    keywords: movieKeywordNames(movie.keywords).slice(0, 24),
    countryCodes: stringArray(movie.countryCodes).slice(0, 12),
    originCountryCodes: stringArray(movie.originCountryCodes).slice(0, 12),
    productionCountries: productionCountryArray(movie.productionCountries)
      .slice(0, 12),
    regionNames: stringArray(movie.regionNames).slice(0, 12),
    countryNames: stringArray(movie.countryNames).slice(0, 12),
    runtime: finiteNumber(movie.runtime),
    director: stringOrEmpty(movie.director),
    cast: Array.isArray(movie.cast) ?
      movie.cast.map((item) => String(item)).slice(0, 8).join(", ") :
      stringOrEmpty(movie.cast),
    trailer,
    trailerKey: trailer ? trailer.key : null,
    trailerSite: trailer ? trailer.site : null,
    trailerUrl: trailer ? trailer.url : null,
    trailerEmbedUrl: trailer ? trailer.embedUrl : null,
    adult: Boolean(movie.adult),
  };

  return isDisplayableMovie(payload) ? payload : null;
}

function sanitizeTrailerPayload(trailer, fallbackKey, fallbackSite) {
  const rawKey = trailer && typeof trailer === "object" ?
    trailer.key :
    fallbackKey;
  const source = trailerSource(
    trailer && typeof trailer === "object" ? trailer.site : fallbackSite,
    rawKey,
  );
  if (!source) {
    return null;
  }

  return {
    ...source,
    name: stringOrEmpty(trailer?.name || "Trailer"),
    type: stringOrEmpty(trailer?.type || "Trailer"),
    official: Boolean(trailer?.official),
  };
}

function trailerSource(site, rawKey) {
  const key = String(rawKey || "").trim();
  // Decisions saved before multi-provider support did not store a site. They
  // were all YouTube trailers, so keep them playable after the update.
  const providerKey = String(site || "YouTube")
    .trim()
    .toLowerCase()
    .replace(/[\s.-]+/g, "");
  const provider = TRAILER_PROVIDERS[providerKey];

  if (!provider || !provider.keyPattern.test(key)) {
    return null;
  }

  return {
    site: provider.site,
    key,
    url: provider.url(key),
    embedUrl: provider.embedUrl(key),
  };
}

async function ensureUserInviteCode(uid) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const snapshot = await userRef.get();
  const data = snapshot.data() || {};
  const existing = normalizeInviteCode(data.friendCode);

  if (existing && await reserveInviteCode(db, userRef, uid, existing)) {
    return existing;
  }

  const start = hashString(uid) % INVITE_CODE_SPACE;
  for (let offset = 0; offset < INVITE_CODE_SPACE; offset += 1) {
    const code = buildInviteCode(start + offset);
    if (await reserveInviteCode(db, userRef, uid, code)) {
      return code;
    }
  }

  const error = new Error("No quedan códigos de invitación disponibles.");
  error.status = 503;
  error.code = "resource-exhausted";
  throw error;
}

async function reserveInviteCode(db, userRef, uid, code) {
  const codeRef = db.collection("friendInviteCodes").doc(code);
  let reserved = false;

  await db.runTransaction(async (transaction) => {
    const reservation = await transaction.get(codeRef);
    if (reservation.exists && reservation.data()?.uid !== uid) {
      return;
    }

    if (!reservation.exists) {
      transaction.create(codeRef, {
        uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.set(userRef, {
      friendCode: code,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    reserved = true;
  });

  return reserved;
}

function normalizeInviteCode(value) {
  const raw = String(value || "")
    .trim()
    .toUpperCase()
    .replace(/[\s-]/g, "");
  if (!new RegExp(`^${INVITE_CODE_PREFIX}\\d{${INVITE_CODE_LENGTH}}$`).test(raw)) {
    return "";
  }

  return raw;
}

function buildInviteCode(value) {
  const suffix = Math.abs(Number(value) || 0) % INVITE_CODE_SPACE;
  return `${INVITE_CODE_PREFIX}${String(suffix).padStart(INVITE_CODE_LENGTH, "0")}`;
}

function hashString(value) {
  let hash = 2166136261;
  const text = String(value || "");
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function displayNameForUser(uid, profile) {
  const displayName = String(profile.displayName || "").trim();
  if (displayName) {
    return displayName;
  }

  const email = String(profile.email || "").trim();
  if (email && email.includes("@")) {
    return email.split("@")[0];
  }

  const code = normalizeInviteCode(profile.friendCode);
  return code ? `Usuario ${code.slice(-4)}` : `Usuario ${uid.slice(0, 4)}`;
}

function initialsForName(name) {
  const parts = String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (!parts.length) {
    return "?";
  }

  return parts
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function colorForUid(uid) {
  const palette = [
    "#E84393",
    "#0FB5A4",
    "#3B82F6",
    "#7B61FF",
    "#FF5A4D",
    "#1F8A5B",
    "#B23A48",
  ];
  return palette[hashString(uid) % palette.length];
}

function stringOrEmpty(value) {
  return value == null ? "" : String(value);
}

function nullableString(value) {
  if (value == null || value === "") {
    return null;
  }

  return String(value);
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function stringArray(value) {
  return Array.isArray(value) ?
    value.map((item) => String(item || "").trim()).filter(Boolean) :
    [];
}

function numberArray(value) {
  return Array.isArray(value) ?
    value.map((item) => Number(item)).filter(Number.isFinite) :
    [];
}

function genreArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((genre) => genre && typeof genre === "object")
    .map((genre) => ({
      id: finiteNumber(genre.id),
      name: stringOrEmpty(genre.name),
    }))
    .filter((genre) => genre.id || genre.name);
}

function productionCountryArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((country) => country && typeof country === "object")
    .map((country) => ({
      code: stringOrEmpty(country.code || country.iso_3166_1).toUpperCase(),
      name: stringOrEmpty(country.name),
    }))
    .filter((country) => country.code || country.name);
}

function isDisplayableMovie(movie) {
  return hasMoviePoster(movie) &&
    hasMovieReleaseDate(movie) &&
    hasMovieRuntime(movie) &&
    !isNonFeatureMovie(movie) &&
    !isPornographicMovie(movie);
}

function hasSearchableMovieBasics(movie) {
  return hasMoviePoster(movie) &&
    hasMovieReleaseDate(movie) &&
    !isNonFeatureMovie(movie) &&
    !isPornographicMovie(movie);
}

function hasMoviePoster(movie) {
  return Boolean(nullableString(movie?.posterPath) ||
    nullableString(movie?.posterUrl));
}

function hasMovieReleaseDate(movie) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(movie?.releaseDate || "").trim());
}

function hasMovieRuntime(movie) {
  const runtime = Number(movie?.runtime);
  return Number.isFinite(runtime) && runtime >= MIN_FEATURE_RUNTIME_MINUTES;
}

function isNonFeatureMovie(movie, details = {}) {
  const runtime = Number(details?.runtime ?? movie?.runtime);
  if (
    Number.isFinite(runtime) &&
    runtime > 0 &&
    runtime < MIN_FEATURE_RUNTIME_MINUTES
  ) {
    return true;
  }

  const keywords = movieKeywordNames(details.keywords)
    .concat(movieKeywordNames(movie?.keywords))
    .join(" ");
  if (containsNonFeatureKeyword(keywords)) {
    return true;
  }

  const text = [
    movie?.title,
    movie?.original_title,
    movie?.originalTitle,
    details?.title,
    details?.original_title,
    details?.originalTitle,
    movie?.overview,
    details?.overview,
  ].join(" ");
  return containsNonFeatureTextMarker(text);
}

function isPornographicMovie(movie, details = {}) {
  if (Boolean(movie?.adult || details?.adult)) {
    return true;
  }

  const keywords = movieKeywordNames(details.keywords)
    .concat(movieKeywordNames(movie?.keywords))
    .join(" ");
  if (containsPornographicMarker(keywords)) {
    return true;
  }

  const text = [
    movie?.title,
    movie?.original_title,
    movie?.originalTitle,
    details?.title,
    details?.original_title,
    details?.originalTitle,
    movie?.overview,
    details?.overview,
  ].join(" ");
  return containsStrongPornographicMarker(text);
}

function movieKeywordNames(value) {
  const source = Array.isArray(value?.keywords) ?
    value.keywords :
    Array.isArray(value?.results) ?
      value.results :
      Array.isArray(value) ? value : [];

  return source
    .map((keyword) => {
      if (keyword && typeof keyword === "object") {
        return String(keyword.name || keyword.title || "");
      }
      return String(keyword || "");
    })
    .filter(Boolean);
}

function normalizedText(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function containsPornographicMarker(value) {
  const text = normalizedText(value);
  return /\b(?:adult film|adult movie|porn|porno|pornografia|pornographic|pornography|hardcore|hard core|x-rated|x rated|xxx|softcore|soft core|sex film|sexploitation)\b/.test(text);
}

function containsStrongPornographicMarker(value) {
  const text = normalizedText(value);
  return /\b(?:porn|porno|pornografia|pornographic|pornography|hardcore|hard core|x-rated|x rated|xxx)\b/.test(text);
}

function containsNonFeatureKeyword(value) {
  const text = normalizedText(value);
  return /\b(?:short film|short movie|short subject|cortometraje|stand-up comedy|stand up comedy|standup comedy|stand-up|stand up|standup|comedy special|tv special|television special|special episode|making of|behind the scenes|talk show|variety show|one-man show|one man show|live performance|stage performance|concert film|concert movie)\b/.test(text);
}

function containsNonFeatureTextMarker(value) {
  const text = normalizedText(value);
  return /\b(?:short film|short movie|short subject|cortometraje|stand-up comedy|stand up comedy|standup comedy|stand-up special|stand up special|standup special|comedy special|tv special|television special|special episode|making of|behind the scenes|talk show|variety show|one-man show|one man show)\b/.test(text);
}

async function fetchTmdbMovies(
  path,
  params,
  fallbackPage,
  enrich = true,
  resultLimit = Infinity,
) {
  const url = `${TMDB_API_BASE_URL}/${path}?${params.toString()}`;
  const tmdbResponse = await fetch(url, {
    headers: {
      accept: "application/json",
      authorization: `Bearer ${tmdbReadToken.value()}`,
    },
  });

  if (!tmdbResponse.ok) {
    const body = await tmdbResponse.text();
    logger.error("TMDB movie request failed", {
      path,
      status: tmdbResponse.status,
      body: body.slice(0, 500),
    });

    const error = new Error("TMDB search is currently unavailable.");
    error.status = 503;
    error.code = "unavailable";
    throw error;
  }

  const payload = await tmdbResponse.json();
  const results = Array.isArray(payload.results) ? payload.results : [];
  const limitedResults = results.slice(0, resultLimit);
  const filteredResults = limitedResults.filter((movie) => !isPornographicMovie(movie));
  const normalizedResults = enrich ?
    await enrichMovies(filteredResults, params.get("language") || "es-ES") :
    filteredResults.map((movie) => normalizeMovie(movie));
  const displayableResults = normalizedResults.filter((movie) => enrich ?
    isDisplayableMovie(movie) :
    hasSearchableMovieBasics(movie));

  return {
    page: Number(payload.page ?? fallbackPage),
    totalPages: Number(payload.total_pages ?? 0),
    totalResults: Number(payload.total_results ?? 0),
    results: displayableResults,
  };
}

async function enrichMovies(movies, language) {
  const enriched = [];
  const concurrency = 5;
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < movies.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      const movie = movies[currentIndex];

      try {
        const details = await fetchMovieDetails(movie.id, language);
        if (
          isPornographicMovie(movie, details) ||
          isNonFeatureMovie(movie, details)
        ) {
          enriched[currentIndex] = null;
          continue;
        }
        enriched[currentIndex] = normalizeMovie(movie, details);
      } catch (error) {
        logger.warn("TMDB movie detail enrichment failed", {
          tmdbId: movie.id,
          message: error.message,
        });
        enriched[currentIndex] = normalizeMovie(movie);
      }
    }
  }

  await Promise.all(
    Array.from({length: Math.min(concurrency, movies.length)}, () => worker()),
  );

  return enriched.filter(Boolean);
}

async function fetchMovieDetails(tmdbId, language) {
  const locale = sanitizeLocale(language, "es-ES");
  const params = new URLSearchParams({
    language: locale,
    append_to_response: "credits,videos,keywords",
  });
  const url = `${TMDB_API_BASE_URL}/movie/${tmdbId}?${params.toString()}`;
  const tmdbResponse = await fetch(url, {
    headers: {
      accept: "application/json",
      authorization: `Bearer ${tmdbReadToken.value()}`,
    },
  });

  if (!tmdbResponse.ok) {
    throw new Error(`TMDB detail request failed with ${tmdbResponse.status}`);
  }

  const details = await tmdbResponse.json();
  if (!selectMovieTrailer(details.videos) && locale !== "en-US") {
    try {
      details.fallbackVideos = await fetchMovieVideos(tmdbId, "en-US");
    } catch (error) {
      logger.warn("TMDB fallback video request failed", {
        tmdbId,
        message: error.message,
      });
    }
  }

  return details;
}

async function fetchMovieVideos(tmdbId, language) {
  const params = new URLSearchParams({
    language: sanitizeLocale(language, "en-US"),
  });
  const url = `${TMDB_API_BASE_URL}/movie/${tmdbId}/videos?${params.toString()}`;
  const tmdbResponse = await fetch(url, {
    headers: {
      accept: "application/json",
      authorization: `Bearer ${tmdbReadToken.value()}`,
    },
  });

  if (!tmdbResponse.ok) {
    throw new Error(`TMDB videos request failed with ${tmdbResponse.status}`);
  }

  return tmdbResponse.json();
}

async function verifyFirebaseAuth(request) {
  const authorization = String(request.get("authorization") || "");
  const match = authorization.match(/^Bearer (.+)$/i);

  if (!match) {
    throw new Error("Missing Firebase ID token.");
  }

  return getAuth().verifyIdToken(match[1]);
}

function sendError(response, status, code, message) {
  response.status(status).json({error: {status, code, message}});
}

function sendCaughtError(response, error) {
  if (error && error.status && error.code) {
    sendError(response, error.status, error.code, error.message);
    return;
  }

  sendError(
    response,
    401,
    "unauthenticated",
    "You must be signed in to search movies.",
  );
}

function normalizeMovie(movie, details = {}) {
  const releaseDate = typeof details.release_date === "string" ?
    details.release_date :
    typeof movie.release_date === "string" ?
      movie.release_date :
      "";
  const posterPath = typeof details.poster_path === "string" ?
    details.poster_path :
    typeof movie.poster_path === "string" ?
      movie.poster_path :
      null;
  const backdropPath = typeof details.backdrop_path === "string" ?
    details.backdrop_path :
    typeof movie.backdrop_path === "string" ?
      movie.backdrop_path :
      null;
  const credits = details.credits || {};
  const crew = Array.isArray(credits.crew) ? credits.crew : [];
  const cast = Array.isArray(credits.cast) ? credits.cast : [];
  const director = crew
    .filter((credit) => credit && credit.job === "Director" && credit.name)
    .map((credit) => String(credit.name))
    .filter((name, index, all) => all.indexOf(name) === index)
    .join(", ");
  const castNames = cast
    .filter((credit) => credit && credit.name)
    .slice(0, 6)
    .map((credit) => String(credit.name));
  const genres = Array.isArray(details.genres) ?
    details.genres
      .filter((genre) => genre && genre.name)
      .map((genre) => ({
        id: Number(genre.id),
        name: String(genre.name),
      })) :
    [];
  const genreIds = genres.length ?
    genres.map((genre) => genre.id).filter(Number.isFinite) :
    Array.isArray(movie.genre_ids) ? movie.genre_ids.map(Number) : [];
  const runtime = Number(details.runtime ?? movie.runtime ?? 0);
  const productionCountries = Array.isArray(details.production_countries) ?
    details.production_countries
      .filter((country) => country && country.iso_3166_1 && country.name)
      .map((country) => ({
        code: String(country.iso_3166_1).toUpperCase(),
        name: String(country.name),
      })) :
    [];
  const originCountryCodes = Array.isArray(movie.origin_country) ?
    movie.origin_country.map((code) => String(code).toUpperCase()) :
    [];
  const countryCodes = uniqueStrings([
    ...originCountryCodes,
    ...productionCountries.map((country) => country.code),
  ]).filter((code) => /^[A-Z]{2}$/.test(code));
  const trailer = selectMovieTrailer(details.videos) ||
    selectMovieTrailer(details.fallbackVideos);
  const keywords = uniqueStrings([
    ...movieKeywordNames(details.keywords),
    ...movieKeywordNames(movie.keywords),
  ]).slice(0, 24);

  return {
    tmdbId: Number(movie.id),
    title: String(movie.title || details.title || movie.original_title || ""),
    originalTitle: String(movie.original_title || details.original_title ||
      movie.title || ""),
    overview: String(movie.overview || details.overview || ""),
    releaseDate,
    year: releaseDate.slice(0, 4) || null,
    posterPath,
    posterUrl: posterPath ? `${TMDB_IMAGE_BASE_URL}/w500${posterPath}` : null,
    backdropPath,
    backdropUrl: backdropPath ?
      `${TMDB_IMAGE_BASE_URL}/w780${backdropPath}` :
      null,
    voteAverage: Number(movie.vote_average ?? details.vote_average ?? 0),
    voteCount: Number(movie.vote_count ?? details.vote_count ?? 0),
    popularity: Number(movie.popularity ?? details.popularity ?? 0),
    originalLanguage: String(movie.original_language ||
      details.original_language || ""),
    genreIds,
    genres,
    keywords,
    countryCodes,
    originCountryCodes: countryCodes,
    productionCountries,
    runtime: Number.isFinite(runtime) ? runtime : 0,
    director,
    cast: castNames,
    trailer,
    trailerKey: trailer ? trailer.key : null,
    trailerSite: trailer ? trailer.site : null,
    trailerUrl: trailer ? trailer.url : null,
    trailerEmbedUrl: trailer ? trailer.embedUrl : null,
    adult: Boolean(movie.adult || details.adult),
  };
}

function selectMovieTrailer(videos) {
  const results = Array.isArray(videos?.results) ? videos.results : [];
  const embeddableVideos = results
    .filter((video) => video && video.key)
    .map((video) => {
      const source = trailerSource(video.site, video.key);
      if (!source) return null;
      return {
        ...source,
        name: String(video.name || "Trailer"),
        type: String(video.type || ""),
        official: Boolean(video.official),
        publishedAt: String(video.published_at || ""),
      };
    })
    .filter(Boolean);

  if (!embeddableVideos.length) {
    return null;
  }

  const rank = (video) => {
    const type = video.type.toLowerCase();
    let score = type === "trailer" ? 40 : type === "teaser" ? 20 : 0;
    if (video.official) score += 10;
    if (/trailer/i.test(video.name)) score += 5;
    return score;
  };
  const [best] = embeddableVideos.sort((left, right) => {
    const scoreDelta = rank(right) - rank(left);
    if (scoreDelta) return scoreDelta;
    return right.publishedAt.localeCompare(left.publishedAt);
  });

  return best;
}

function uniqueStrings(values) {
  return Array.from(new Set(values.map((value) => String(value || "").trim())
    .filter(Boolean)));
}

function shuffleValues(values) {
  const copy = values.slice();
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function sanitizeLocale(value, fallback) {
  const locale = String(value ?? fallback);
  return /^[a-z]{2}-[A-Z]{2}$/.test(locale) ? locale : fallback;
}

function sanitizeRegion(value, fallback) {
  const region = String(value ?? fallback);
  return /^[A-Z]{2}$/.test(region) ? region : fallback;
}

function sanitizePage(value) {
  const page = Number.parseInt(String(value ?? "1"), 10);
  if (!Number.isFinite(page)) {
    return 1;
  }

  return Math.min(Math.max(page, 1), 500);
}

function sanitizeGenreIds(value) {
  const source = Array.isArray(value) ? value : String(value ?? "").split(/[|,]/);
  return source
    .map((item) => Number.parseInt(String(item), 10))
    .filter((item) => Number.isFinite(item) && item > 0)
    .slice(0, 8);
}

function sanitizeCountryCodes(value) {
  const source = Array.isArray(value) ? value : String(value ?? "").split(/[|,]/);
  return uniqueStrings(source.map((item) => String(item).toUpperCase()))
    .filter((item) => /^[A-Z]{2}$/.test(item))
    .slice(0, 40);
}

function sanitizeYear(value) {
  const year = Number.parseInt(String(value ?? ""), 10);
  const maxYear = new Date().getUTCFullYear() + 1;

  if (!Number.isFinite(year) || year < 1874 || year > maxYear) {
    return null;
  }

  return year;
}

function sanitizeVoteAverage(value) {
  const rating = Number.parseFloat(String(value ?? ""));

  if (!Number.isFinite(rating) || rating < 1 || rating > 10) {
    return null;
  }

  return Math.round(rating * 10) / 10;
}

function sanitizeSortBy(value) {
  const allowed = new Set([
    "popularity.desc",
    "vote_count.desc",
    "primary_release_date.desc",
    "revenue.desc",
  ]);
  const requested = String(value ?? "");

  if (allowed.has(requested)) {
    return requested;
  }

  const fallback = Array.from(allowed);
  return fallback[Math.floor(Math.random() * fallback.length)];
}
