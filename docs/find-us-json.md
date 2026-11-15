# Find an agent: optional JSON feed for nchemty.com

The app's **Find an agent** screen lists branches and agents by distance and
starts navigation. Today it reads the cards of `https://nchemty.com/find-us`
(the coordinates in each "Directions" link). That works, but a website
redesign could break it. A small JSON feed makes it robust.

Serve it at **`https://nchemty.com/find-us.json`** (or set
`--dart-define=FIND_US_JSON_URL=...`). The app uses it automatically when it
exists and falls back to the page otherwise.

```json
[
  {
    "name": "SR Enterprise",
    "type": "Agent",
    "town": "Buea",
    "landmark": "Opposite Congelcam",
    "services": ["Cash in", "Cash out"],
    "lat": 4.1601,
    "lng": 9.2432,
    "phone": "+237699000002",
    "whatsapp": "https://wa.me/237699000002"
  }
]
```

- Required: `name`, `lat`, `lng`. Everything else optional.
- `type`: `Branch` or `Agent`. `address` may replace `town` + `landmark`.
- Only list active, verified agents; the app shows whatever the feed returns.
- `{"locations": [...]}` is also accepted.
