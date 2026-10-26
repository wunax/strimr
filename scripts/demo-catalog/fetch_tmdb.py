#!/usr/bin/env python3
"""Builds the screenshot demo catalog from TMDB.

Reads Screenshots/DemoContent/selection.json, writes catalog.json (or catalog.<lang>.json) and the artwork next to it.
The TMDB credential comes from TMDB_API_TOKEN (read access token) or TMDB_API_KEY (v3 key), in the environment or in
the repository's .env file.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CONTENT = REPO / "Screenshots" / "DemoContent"
SELECTION = CONTENT / "selection.json"
# Resolved TMDB ids, kept apart from selection.json so its hand-written layout survives.
RESOLVED_IDS = CONTENT / "tmdb-ids.json"

API = "https://api.themoviedb.org/3"
IMAGES = "https://image.tmdb.org/t/p"
POSTER_SIZE = "w780"
BACKDROP_SIZE = "original"
LOGO_SIZE = "w500"
PROFILE_SIZE = "h632"
STILL_SIZE = "original"
CAST_LIMIT = 12


def load_credentials():
    values = dict(os.environ)
    env_file = REPO / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and not key.startswith("#"):
                values.setdefault(key.strip(), value.strip().strip("'\""))
    token = values.get("TMDB_API_TOKEN")
    key = values.get("TMDB_API_KEY")
    if not token and not key:
        sys.exit("Missing TMDB_API_TOKEN or TMDB_API_KEY (environment or .env)")
    return token, key


class TMDB:
    def __init__(self, token, key):
        self.token = token
        self.key = key

    def get(self, path, **params):
        if self.key and not self.token:
            params["api_key"] = self.key
        url = f"{API}{path}?{urllib.parse.urlencode(params)}"
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                if error.code == 429 and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                # The URL may carry the API key, so only the path is reported.
                sys.exit(f"TMDB {error.code} on {path}")
        return None


def download(path, size, destination):
    if not path:
        return None
    target = CONTENT / destination
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(f"{IMAGES}/{size}{path}", timeout=60) as response:
            target.write_bytes(response.read())
    return destination


def best_image(images, languages):
    """Highest voted image in the first language of `languages` that has one; None stands for textless images."""
    for language in languages:
        candidates = [image for image in images if image.get("iso_639_1") == language]
        if candidates:
            return max(candidates, key=lambda image: (image.get("vote_average", 0), image.get("width", 0)))
    return None


def localized(value, language):
    if isinstance(value, dict):
        return value.get(language) or value.get("en") or next(iter(value.values()))
    return value


def resolve_ids(tmdb, items):
    resolved = json.loads(RESOLVED_IDS.read_text()) if RESOLVED_IDS.exists() else {}
    changed = False
    for item in items:
        if item["id"] in resolved:
            continue
        kind = "movie" if item["type"] == "movie" else "tv"
        year_param = "primary_release_year" if kind == "movie" else "first_air_date_year"
        results = tmdb.get(f"/search/{kind}", query=item["title"], **{year_param: item["year"]})["results"]
        if not results:
            results = tmdb.get(f"/search/{kind}", query=item["title"])["results"]
        if not results:
            sys.exit(f"No TMDB match for {item['title']} ({item['year']})")
        match = results[0]
        resolved[item["id"]] = match["id"]
        changed = True
        found = match.get("title") or match.get("name")
        date = match.get("release_date") or match.get("first_air_date") or "?"
        print(f"  {item['id']} → {match['id']} ({found}, {date})")
    if changed:
        RESOLVED_IDS.write_text(json.dumps(resolved, indent=2, ensure_ascii=False) + "\n")
    return resolved


def certification(details, kind, country):
    if kind == "movie":
        for entry in details.get("release_dates", {}).get("results", []):
            if entry["iso_3166_1"] == country:
                for release in entry["release_dates"]:
                    if release.get("certification"):
                        return release["certification"]
    else:
        for entry in details.get("content_ratings", {}).get("results", []):
            if entry["iso_3166_1"] == country and entry.get("rating"):
                return entry["rating"]
    return None


def episode_code(code):
    season, _, episode = code.upper().removeprefix("S").partition("E")
    return int(season), int(episode)


def build_item(tmdb, item, tmdb_id, locale, people):
    language, _, country = locale.partition("-")
    country = country or "US"
    kind = "movie" if item["type"] == "movie" else "tv"
    extras = "credits,images," + ("release_dates" if kind == "movie" else "content_ratings")
    details = tmdb.get(
        f"/{kind}/{tmdb_id}",
        language=locale,
        append_to_response=extras,
        include_image_language=f"{language},en,null",
    )
    images = details.get("images", {})
    image_languages = [language, "en", None]
    poster = best_image(images.get("posters", []), image_languages)
    logo = best_image(images.get("logos", []), [language, "en"])
    backdrop = best_image(images.get("backdrops", []), [None, "en"])
    poster_language = poster.get("iso_639_1") if poster else None
    logo_language = logo.get("iso_639_1") if logo else None

    cast = []
    for member in details.get("credits", {}).get("cast", [])[:CAST_LIMIT]:
        person_id = f"person-{member['id']}"
        if person_id not in people:
            people[person_id] = {
                "id": person_id,
                "name": member["name"],
                "photo": download(member.get("profile_path"), PROFILE_SIZE, f"people/{member['id']}.jpg"),
            }
        cast.append({"person": person_id, "role": member.get("character") or None})
    crew = details.get("credits", {}).get("crew", [])
    directors = [member["name"] for member in crew if member.get("job") == "Director"]
    creators = [creator["name"] for creator in details.get("created_by", [])]

    entry = {
        "id": item["id"],
        "tmdbID": tmdb_id,
        "type": item["type"],
        "library": item["library"],
        "title": details.get("title") or details.get("name"),
        "originalTitle": details.get("original_title") or details.get("original_name"),
        "tagline": details.get("tagline") or None,
        "summary": details.get("overview") or None,
        "releaseDate": details.get("release_date") or details.get("first_air_date") or None,
        "genres": [genre["name"] for genre in details.get("genres", [])],
        "rating": round(details.get("vote_average", 0), 1) or None,
        "contentRating": certification(details, kind, country),
        "studio": next(
            (company["name"] for company in details.get("networks", []) or details.get("production_companies", [])),
            None,
        ),
        "directors": directors or creators,
        "cast": cast,
        "poster": download(
            poster and poster["file_path"], POSTER_SIZE, f"posters/{item['id']}-{poster_language or 'none'}.jpg"
        ),
        "backdrop": download(backdrop and backdrop["file_path"], BACKDROP_SIZE, f"backdrops/{item['id']}.jpg"),
        "logo": download(logo and logo["file_path"], LOGO_SIZE, f"logos/{item['id']}-{logo_language}.png"),
        "progress": item.get("progress"),
    }
    if entry["releaseDate"]:
        entry["year"] = int(entry["releaseDate"][:4])

    if kind == "movie":
        entry["duration"] = (details.get("runtime") or 0) * 60 or None
        return entry

    detailed_seasons = set(item.get("seasons", []))
    for code in filter(None, [item.get("nextUp"), item.get("continue", {}).get("episode")]):
        detailed_seasons.add(episode_code(code)[0])
    seasons = []
    for season in details.get("seasons", []):
        number = season["season_number"]
        if number == 0:
            continue
        season_entry = {
            "id": f"{item['id']}-s{number:02d}",
            "number": number,
            "title": season.get("name"),
            "summary": season.get("overview") or None,
            "episodeCount": season.get("episode_count"),
            "poster": download(season.get("poster_path"), POSTER_SIZE, f"posters/{item['id']}-s{number:02d}.jpg"),
        }
        if number in detailed_seasons:
            season_details = tmdb.get(f"/tv/{tmdb_id}/season/{number}", language=locale)
            season_entry["episodes"] = [
                {
                    "id": f"{item['id']}-s{number:02d}e{episode['episode_number']:02d}",
                    "number": episode["episode_number"],
                    "title": episode.get("name"),
                    "summary": episode.get("overview") or None,
                    "airDate": episode.get("air_date") or None,
                    "duration": (episode.get("runtime") or 0) * 60 or None,
                    "still": download(
                        episode.get("still_path"),
                        STILL_SIZE,
                        f"stills/{item['id']}-s{number:02d}e{episode['episode_number']:02d}.jpg",
                    ),
                }
                for episode in season_details.get("episodes", [])
            ]
        seasons.append(season_entry)
    entry["seasons"] = seasons
    if item.get("nextUp"):
        season, episode = episode_code(item["nextUp"])
        entry["nextUp"] = f"{item['id']}-s{season:02d}e{episode:02d}"
    if item.get("continue"):
        season, episode = episode_code(item["continue"]["episode"])
        entry["continue"] = {
            "episode": f"{item['id']}-s{season:02d}e{episode:02d}",
            "progress": item["continue"]["progress"],
        }
    return entry


def build_catalog(tmdb, selection, resolved, locale):
    language = locale.partition("-")[0]
    people = {}
    items = []
    for item in selection["items"]:
        print(f"  {item['id']}")
        items.append(build_item(tmdb, item, resolved[item["id"]], locale, people))

    def hub(row):
        return {
            key: localized(value, language) if key == "title" else value
            for key, value in row.items()
        }

    return {
        "language": locale,
        "server": selection["server"],
        "libraries": [
            {
                "id": library["id"],
                "title": localized(library["title"], language),
                "type": library["type"],
                "items": [item["id"] for item in selection["items"] if item["library"] == library["id"]],
                "recommended": [hub(row) for row in library.get("recommended", [])],
            }
            for library in selection["libraries"]
        ],
        "rows": [hub(row) for row in selection["rows"]],
        "items": items,
        "people": sorted(people.values(), key=lambda person: person["id"]),
        "player": selection.get("player"),
    }


def validate(selection):
    item_ids = {item["id"] for item in selection["items"]}
    rows = selection["rows"] + [row for library in selection["libraries"] for row in library.get("recommended", [])]
    unknown = {item for row in rows for item in row["items"] if item not in item_ids}
    if selection.get("player") and selection["player"]["item"] not in item_ids:
        unknown.add(selection["player"]["item"])
    if unknown:
        sys.exit(f"Unknown item ids in selection.json: {', '.join(sorted(unknown))}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--languages", default="en-US", help="Comma-separated TMDB locales, e.g. en-US,fr-FR")
    arguments = parser.parse_args()

    selection = json.loads(SELECTION.read_text())
    validate(selection)
    tmdb = TMDB(*load_credentials())
    print("Resolving TMDB ids")
    resolved = resolve_ids(tmdb, selection["items"])
    locales = [locale.strip() for locale in arguments.languages.split(",") if locale.strip()]
    for index, locale in enumerate(locales):
        print(f"Building catalog for {locale}")
        catalog = build_catalog(tmdb, selection, resolved, locale)
        name = "catalog.json" if index == 0 else f"catalog.{locale.partition('-')[0]}.json"
        (CONTENT / name).write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
        print(f"Wrote {name}")


if __name__ == "__main__":
    main()
