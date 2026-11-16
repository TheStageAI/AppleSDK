# Embeddings

Turns text, photos, audio and video into vectors you can compare. Things
that mean the same land close together, whatever the input — so a typed
question finds the right paragraph, the right photo, or the right moment
in a recording, on device, without sending anything to a server.

Use it in two ways: embed what you want to search once and store the
vectors, then embed each query and rank by similarity; or compare two
items directly to group, deduplicate or classify them.

> **Main features**
>
> - **One space for every input**: text, images, audio, video, and an
>   image with its caption are all comparable with each other.
> - **One call per item**: `infer(text:)`, `infer(image:)`,
>   `infer(audio:sample_rate:)`, `infer(video:)` or
>   `infer(inputs:)` on Swift; `infer(model_name: 'embed', …)` on
>   Flutter.
> - **Task prompts**: tell the model whether a text is a search query, a
>   document, or input for classification, clustering or similarity.
> - **Pick the vector size**: 768, 512, 256 or 128 values — smaller
>   vectors take less storage and rank faster, at a small cost in
>   quality.
> - **Load only what you use**: open the model for text only, or add
>   images, audio and video when you need them.

## In this page

Here we will cover the following topics:

- [Supported models](#supported-models): the model, what each input accepts, and which vector size to pick.
- [Quick start](#quick-start): text search and photo search — Swift and Flutter side by side.
- [Embed text](#embed-text): task prompts for queries, documents and other tasks.
- [Embed images](#embed-images): photos and screenshots, searchable by text.
- [Embed audio](#embed-audio): sounds and speech up to 30 seconds.
- [Embed video](#embed-video): a clip as one vector, and how many frames it reads.
- [Mixed input](#mixed-input): an image and its caption as one item.
- [Vector sizes and similarity](#vector-sizes-and-similarity): smaller vectors, comparing results safely.
- [Result object](#result-object): `EmbeddingResult` fields and their Flutter JSON keys.
- [Usage Guides](#usage-guides): on-device search over a large library.
- [Troubleshooting](#troubleshooting): symptom → cause → fix.
- [Load Progress / Prefetch / Cleanup](#load-progress-prefetch-cleanup): first-run download, warming the cache, releasing the model.

## Supported models

| Model | HF repo | Base | Device | Fleet pin |
|---|---|---|---|---|
| EmbeddingGemma 2 | `TheStageAI/embeddinggemma-2` | `google/embeddinggemma-2` | NPU | v1.6 |

Requires SDK **1.6.0** or later.

| Input | Accepts | Limit |
|---|---|---|
| Text | any string | 2048 tokens (about 1500 words); longer text is cut and the result says `truncated` |
| Image | `CGImage` (Swift), a file path (Flutter) | any size; resized for you |
| Audio | mono samples at any rate (Swift), a WAV path (Flutter) | first 30 s; longer audio is cut and the result says `truncated` |
| Video | a file URL (Swift), a file path (Flutter) | one frame per second, at most 14 frames by default |
| Mixed | several of the above as one item | 2048 tokens in total |
| Output | unit-length vector | 768, 512, 256 or 128 values |

**Which size?**

| You need… | Pick | Why |
|---|---|---|
| Best ranking quality | **768** | The default; the full vector. |
| A large text or photo index on a phone | **256** | A third of the storage; text ranking quality is almost unchanged. |
| A fast first pass over everything, re-ranked afterwards | **128** or **256** | See [On-device search over a large library](#on-device-search-over-a-large-library). |
| Image, audio or video search at the smallest size | **256**, not 128 | 128 loses noticeably more on non-text inputs. |

## Quick start

Every use is the same three steps: load the model once, embed each
item, compare vectors. What changes is which `infer` you call.

| You want | Embed | Use |
|---|---|---|
| Search notes, help articles or messages by meaning | queries and documents as text | `infer(text:task:)` with `.QUERY` / `.DOCUMENT` |
| Find photos by describing them | photos once, the description per search | `infer(image:)` + `infer(text:task: .QUERY)` |
| Find a sound, a recording or a clip | the media once, the description per search | `infer(audio:sample_rate:)` / `infer(video:)` |
| Treat a product photo and its title as one item | both together | `infer(inputs:)` |

### Search text by meaning

**Swift**

```swift
import TheStageSDK

try await TheStageAI.shared.initialize(api_token: "your-api-token")

let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT]
)

let query: EmbeddingResult = try await embedder.infer(
    text: "how do I reset the router", task: .QUERY
)
let doc: EmbeddingResult = try await embedder.infer(
    text: "Hold the reset button for ten seconds until the light blinks.",
    task: .DOCUMENT
)
// higher = closer in meaning
let score: Float = try EmbeddingPipeline.similarity(query, doc)
print(score)
```

**Flutter**

```dart
import 'package:thestage_apple_sdk/thestage_apple_sdk.dart';

// Vectors are unit length: the dot product is the cosine similarity.
double similarity(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'embed',
  engines_path: 'TheStageAI/embeddinggemma-2',
);

final query = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': 'how do I reset the router', 'task': 'query'},
);
final doc = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {
    'text': 'Hold the reset button for ten seconds until the light blinks.',
    'task': 'document',
  },
);
final score = similarity(
  (query[0]['embedding'] as List).cast<double>(),
  (doc[0]['embedding'] as List).cast<double>(),
);
print(score);
```

### Find photos by describing them

**Swift**

```swift
let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT, .IMAGE]
)

// Once per photo, when it is added to the library
let photo: CGImage = try ImageIOHelpers.load_cgimage(path: "/path/to/beach.jpg")
let photo_vector: EmbeddingResult = try await embedder.infer(image: photo)

// Per search
let query: EmbeddingResult = try await embedder.infer(
    text: "a dog running on the beach", task: .QUERY
)
let score: Float = try EmbeddingPipeline.similarity(query, photo_vector)
```

**Flutter**

```dart
// Once per photo
final photo = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'image_path': '/path/to/beach.jpg'},
);
final photoVector = (photo[0]['embedding'] as List).cast<double>();

// Per search
final query = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': 'a dog running on the beach', 'task': 'query'},
);
final score = similarity(
  (query[0]['embedding'] as List).cast<double>(),
  photoVector,
);
```

### Important API

| Purpose | Swift | Flutter |
|---|---|---|
| Load the model | `try await EmbeddingPipeline(engines_path:modalities:)` | `start_model(model_name: 'embed', engines_path:)` |
| Embed text | `infer(text:task:dimension:)` | `infer(…, input_json: {'text': …, 'task': …})` |
| Embed an image | `infer(image:task:dimension:)` | `{'image_path': …}` |
| Embed audio | `infer(audio:sample_rate:task:dimension:)` | `{'audio_path': …}` |
| Embed a video | `infer(video:max_frames:task:dimension:)` | `{'video_path': …, 'max_frames': …}` |
| Several inputs as one item | `infer(inputs:task:dimension:)` | several keys in one `input_json` |
| Compare two results | `EmbeddingPipeline.similarity(_:_:)` | dot product of the two `embedding` lists |
| Release | drop the pipeline | `stop_model(model_name: 'embed')` |

## Embed text

Search works best when the model knows which side of the search a text
is on. A short question and the long paragraph that answers it look
different; the task prompt tells the model to put them close anyway.

**Swift**

```swift
// Index: every article, once
let article: EmbeddingResult = try await embedder.infer(
    text: article_text, task: .DOCUMENT
)

// Search: the user's question
let question: EmbeddingResult = try await embedder.infer(
    text: "why does my battery drain overnight", task: .QUERY
)

// Grouping support tickets: the same task on every item
let ticket: EmbeddingResult = try await embedder.infer(
    text: ticket_text, task: .CLUSTERING
)
if ticket.truncated {
    // the text was longer than the model reads; only the start was used
}
```

**Flutter**

```dart
// Index: every article, once
final article = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': articleText, 'task': 'document'},
);

// Search: the user's question
final question = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {
    'text': 'why does my battery drain overnight',
    'task': 'query',
  },
);

// Grouping support tickets: the same task on every item
final ticket = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': ticketText, 'task': 'Clustering'},
);
final cut = ticket[0]['truncated'] as bool;
```

**Task prompts** — `task:` (Swift `EmbeddingTask`) / `'task'`
(Flutter string):

| Swift | Flutter | Use for |
|---|---|---|
| `.QUERY` | `'query'` | The search text the user types. |
| `.DOCUMENT` | `'document'` | Everything in the index that a query should find. |
| `.SENTENCE_SIMILARITY` | `'STS'` | Two texts of the same kind compared directly (duplicates, paraphrases). Use it on both. |
| `.CLASSIFICATION` | `'Classification'` | Texts you feed to your own classifier or compare against labels. |
| `.CLUSTERING` | `'Clustering'` | Texts you group by topic. |
| `.CODE_RETRIEVAL` | `'CodeRetrieval'` | A natural-language question searching code. |
| `.QUESTION_ANSWERING` | `'QuestionAnswering'` | A question searching for the passage that answers it. |
| `.FACT_CHECKING` | `'FactChecking'` | A claim searching for evidence. |
| `nil` (default) | key omitted | No prompt. Use only when every item you compare also has none. |

> [!TIP]
> - Queries and documents must use **different** prompts —
>   `.QUERY` and `.DOCUMENT`. Using no prompt, or the same one on both
>   sides, still returns vectors; search just ranks worse.
> - If you change prompts, re-embed the whole index. Vectors made with
>   different prompts do not mix well.

## Embed images

A photo becomes a vector in the same space as text, so a typed
description finds it without tags or captions. Pass the image at its
original size — resizing is done for you.

**Swift**

```swift
let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT, .IMAGE]
)

let screenshot: CGImage = try ImageIOHelpers.load_cgimage(
    path: "/path/to/screenshot.png"
)
let vector: EmbeddingResult = try await embedder.infer(image: screenshot)
// vector.token_count: about 260 for any image
```

**Flutter**

```dart
final rows = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'image_path': '/path/to/screenshot.png'},
);
final vector = (rows[0]['embedding'] as List).cast<double>();
```

| Field | Default | When you would change it |
|---|---|---|
| `image` / `'image_path'` | — | Any format ImageIO reads (JPEG, PNG, HEIC). Do not pre-resize. |
| `task` | none | Leave unset for library items; the text query carries `.QUERY`. |

## Embed audio

A sound or a short recording becomes a vector you can find by
describing it — "doorbell", "applause", "someone laughing" — or match
against other clips.

**Swift**

```swift
let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT, .AUDIO]
)

let samples: [Float] = try AudioIO.load_wav(
    path: "/path/to/clip.wav",
    target_sample_rate: 16_000
)
let clip: EmbeddingResult = try await embedder.infer(
    audio: samples, sample_rate: 16_000
)
if clip.truncated {
    // the clip was longer than 30 s; only the first 30 s were used
}
```

**Flutter**

```dart
final rows = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'audio_path': '/path/to/clip.wav'},
);
final clip = (rows[0]['embedding'] as List).cast<double>();
final cut = rows[0]['truncated'] as bool;
```

| Field | Default | When you would change it |
|---|---|---|
| `audio` + `sample_rate` | — | Mono `[Float]` at any rate; it is resampled for you. Stereo: mix to mono first. |
| `'audio_path'` (Flutter) | — | Any file AVFoundation reads; converted to mono 16 kHz for you. |
| Length | first 30 s | For longer recordings, embed 30 s pieces and store one vector each. |

## Embed video

A clip becomes one vector from frames read once per second. Use it to
find a video by describing it, or to group similar clips.

**Swift**

```swift
let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT, .VIDEO]
)

let clip: EmbeddingResult = try await embedder.infer(
    video: URL(fileURLWithPath: "/path/to/clip.mov"),
    // fewer frames: faster, less detail
    max_frames: 8
)
```

**Flutter**

```dart
final rows = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'video_path': '/path/to/clip.mov', 'max_frames': 8},
);
final clip = (rows[0]['embedding'] as List).cast<double>();
```

| Field | Default | When you would change it |
|---|---|---|
| `max_frames` | `14` | Lower it for speed, or when the video comes with long text in the same `inputs`. Higher values are capped at 14. |
| Frame rate | 1 frame per second | Fixed. Clips longer than 14 s are sampled evenly across their length. A clip under 1 s gives one frame. |

Already decoded the frames yourself? Pass them in order with
`infer(inputs: [.video_frames(frames)])` (Swift).

## Mixed input

Some items are more than one thing: a product photo with its title, a
slide with its speaker notes. Embedding them together gives one vector
that matches searches for either.

**Swift**

```swift
let product: EmbeddingResult = try await embedder.infer(
    inputs: [.image(product_photo), .text("red running sneakers, size 42")]
)
```

**Flutter**

```dart
final rows = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {
    'text': 'red running sneakers, size 42',
    'image_path': '/path/to/product.jpg',
  },
);
```

| Behaviour | Detail |
|---|---|
| Order | Swift uses the order of `inputs`. Flutter always uses text, then image, audio, video. |
| Parts | Any mix of `.text`, `.image`, `.audio`, `.video`, `.video_frames`; each kind must be loaded (`modalities`). |
| Limit | 2048 tokens for the whole item. Media is never cut: an item that does not fit throws — lower `max_frames` or shorten the text. |

## Vector sizes and similarity

The first 512, 256 or 128 values of a vector are themselves a usable
vector. Smaller vectors cut storage and make ranking faster; quality
drops only a little down to 256.

**Swift**

```swift
// [768, 512, 256, 128]
print(embedder.matryoshka_dims)

let a: EmbeddingResult = try await embedder.infer(
    text: "wireless headphones", task: .QUERY, dimension: 256
)
let b: EmbeddingResult = try await embedder.infer(
    text: "Bluetooth earbuds with noise cancelling", task: .DOCUMENT, dimension: 256
)
let score: Float = try EmbeddingPipeline.similarity(a, b)

// Throws: a 256-value and a 768-value vector are not comparable
let full: EmbeddingResult = try await embedder.infer(text: "wireless headphones", task: .QUERY)
_ = try? EmbeddingPipeline.similarity(full, b)
```

**Flutter**

```dart
final a = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': 'wireless headphones', 'task': 'query', 'dimension': 256},
);
final b = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {
    'text': 'Bluetooth earbuds with noise cancelling',
    'task': 'document',
    'dimension': 256,
  },
);
// Compare only results with the same embedding_space_id
assert(a[0]['embedding_space_id'] == b[0]['embedding_space_id']);
final score = similarity(
  (a[0]['embedding'] as List).cast<double>(),
  (b[0]['embedding'] as List).cast<double>(),
);
```

Reference quality of the base model at each size (Google, bf16; higher
is better):

| Size | Text (MTEB eng v2) | Code (MTEB Code) | Images (MIEB lite) | Audio (MAEB) | Video and mixed (MMEB v2) |
|---|---|---|---|---|---|
| 768 | 68.46 | 78.68 | 65.67 | 49.87 | 59.01 |
| 512 | 68.41 | 77.24 | 65.34 | 49.76 | 58.38 |
| 256 | 67.78 | 76.18 | 64.16 | 49.13 | 56.24 |
| 128 | 65.68 | 71.41 | 59.97 | 47.28 | 45.65 |

| Field | Default | When you would change it |
|---|---|---|
| `dimension` | `768` | `512` / `256` / `128` to save storage. Any other value throws. |
| `similarity` | — | Cosine similarity in `[-1, 1]`. Throws when the two results come from different sizes or different model versions. |

> [!TIP]
> - Never compare vectors of different sizes, and never cut a stored
>   vector to fewer values without scaling it back to unit length — see
>   the usage guide below for the right way.
> - Store `embedding_space_id` next to your vectors. If it changes (a
>   new model version), re-embed the index.

## Result object

`EmbeddingResult` is what every `infer` returns. Flutter gets the
same fields as JSON.

**Swift**

```swift
let result: EmbeddingResult = try await embedder.infer(text: "hello", task: .QUERY)

// [Float], unit length
result.embedding
// 768, or the dimension you asked for
result.dimension
// store with the vector; compare only equal ids
result.embedding_space_id
// how much input the model read
result.token_count
// text or audio was cut to fit
result.truncated
```

**Flutter**

```dart
final rows = await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {'text': 'hello', 'task': 'query'},
);
final row = rows[0];
final embedding = (row['embedding'] as List).cast<double>();
final dimension = row['dimension'] as int;
final spaceId = row['embedding_space_id'] as String;
final tokens = row['token_count'] as int;
final truncated = row['truncated'] as bool;
```

| Swift | Flutter JSON | Meaning |
|---|---|---|
| `embedding` | `embedding` | The vector, unit length: `[Float]` in Swift, a list of doubles in Flutter. |
| `dimension` | `dimension` | Number of values: 768, 512, 256 or 128. |
| `embedding_space_id` | `embedding_space_id` | Identifies the model version and size. Two vectors are comparable only when these are equal. |
| `token_count` | `token_count` | Length of what the model read (text, prompt and media). |
| `truncated` | `truncated` | `true` when text past 2048 tokens or audio past 30 s was left out. |

## Usage Guides

Each guide is one app we are building: what it is, what users expect,
what to use from the SDK, and the code.

### On-device search over a large library

> **Problem**
>
> **Building** — a notes app with ten thousand notes and photos, and a
> search box.
>
> **Users want** — type "receipt from the hardware store" and see the
> right note or photo first, instantly, offline.
>
> **Hard part** — comparing the query with every full vector on each
> keystroke is slow on a phone, and smaller vectors alone rank a little
> worse.

**Solution — what to use**

- `infer(text:task: .DOCUMENT)` / `infer(image:)` — embed each item
  once when it is saved; store the full 768-value vector and its
  `embedding_space_id`.
- When indexing, also store the first 256 values scaled back to unit
  length — the same vector `dimension: 256` would return.
- Per search: `infer(text:task: .QUERY)` once, shortlist with the 256
  values against every item, then re-rank only the shortlist with the
  full 768 values.
- Re-embed everything when the stored `embedding_space_id` differs
  from a fresh result's.

**Swift**

```swift
struct IndexedItem {
    let id: String
    let full: [Float]
    let short: [Float]
}

// The first `size` values, scaled back to unit length
func shortened(_ v: [Float], to size: Int) -> [Float] {
    let head = Array(v.prefix(size))
    let norm = head.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
    return head.map { $0 / norm }
}

func dot(_ a: [Float], _ b: [Float]) -> Float {
    zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
}

// Indexing, once per note
let note: EmbeddingResult = try await embedder.infer(text: note_text, task: .DOCUMENT)
index.append(IndexedItem(
    id: note_id, full: note.embedding, short: shortened(note.embedding, to: 256)
))

// Search
let query: EmbeddingResult = try await embedder.infer(text: search_text, task: .QUERY)
let query_short = shortened(query.embedding, to: 256)
let shortlist = index
    .sorted { dot(query_short, $0.short) > dot(query_short, $1.short) }
    .prefix(100)
let results = shortlist
    .sorted { dot(query.embedding, $0.full) > dot(query.embedding, $1.full) }
```

**Flutter**

```dart
import 'dart:math';

class IndexedItem {
  IndexedItem(this.id, this.full, this.short);
  final String id;
  final List<double> full;
  final List<double> short;
}

// The first `size` values, scaled back to unit length
List<double> shortened(List<double> v, int size) {
  final head = v.sublist(0, size);
  final norm = sqrt(head.fold(0.0, (s, x) => s + x * x));
  return head.map((x) => x / norm).toList();
}

Future<List<double>> embed(String text, String task) async {
  final rows = await TheStageFlutterSDK.infer(
    model_name: 'embed',
    input_json: {'text': text, 'task': task},
  );
  return (rows[0]['embedding'] as List).cast<double>();
}

// Indexing, once per note
final note = await embed(noteText, 'document');
index.add(IndexedItem(noteId, note, shortened(note, 256)));

// Search
final query = await embed(searchText, 'query');
final queryShort = shortened(query, 256);
final shortlist = [...index]
  ..sort((a, b) => similarity(queryShort, b.short)
      .compareTo(similarity(queryShort, a.short)));
final results = shortlist.take(100).toList()
  ..sort((a, b) => similarity(query, b.full)
      .compareTo(similarity(query, a.full)));
```

> [!TIP]
> - Scale the shortened vector back to unit length. A plain cut of the
>   first 256 values ranks wrong without any error.
> - Embed the query once at full size and shorten it locally — one
>   `infer` per search, not two.
> - 256 is the safe shortlist size for photos, audio and video; 128
>   works well for text-only libraries.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Search finds unrelated items first | Queries and documents embedded with the same prompt, or none. | `.QUERY` for searches, `.DOCUMENT` for the index; re-embed the index. See [Embed text](#embed-text). |
| Scores got worse after switching to 256 values | Stored vectors cut without scaling back to unit length. | See [On-device search over a large library](#on-device-search-over-a-large-library). |
| `similarity` throws "Incompatible embeddings" | Different sizes, or vectors from a different model version. | Compare equal `embedding_space_id` only; re-embed after an update. |
| "Not supported: image input is not loaded" | The pipeline was opened without that input in `modalities`. | Add `.IMAGE` / `.AUDIO` / `.VIDEO` when you load. |
| "Not supported: dimension …" | `dimension` is not 768, 512, 256 or 128. | Use one of `embedder.matryoshka_dims`. |
| "Input needs … tokens" on a video | Too many frames together with long text. | Lower `max_frames` or shorten the text. |
| `truncated` is `true` | Text past 2048 tokens or audio past 30 s. | Split long content and store one vector per piece. |
| "Invalid media input" on a video | The file has no video track or cannot be read. | Check the file plays in AVFoundation; re-encode to H.264 / HEVC. |
| First load is slow | The first run downloads and prepares the model for this device. | Prefetch on a splash screen; load only the inputs you use. |
| Model load fails | `initialize` not called. | `initialize(api_token:)` first. |

## Load Progress / Prefetch / Cleanup

First run downloads and prepares the model; later runs hit the cache.
Show progress the first time, warm the cache on a splash screen, and
release the model when you are done.

**Swift**

```swift
let ai = TheStageAI.shared

// Progress
let embedder = try await EmbeddingPipeline(
    engines_path: "TheStageAI/embeddinggemma-2",
    modalities: [.TEXT, .IMAGE],
    on_load_progress: { p in
        print("[\(p.model)] \(p.phase) \(Int(p.fraction * 100))%")
    }
)

// Prefetch on a splash screen, construct later
let engines_dir = try await ai.prefetch_engines(
    repo_id: "TheStageAI/embeddinggemma-2"
)
let warm_embedder = try await EmbeddingPipeline(engines_path: engines_dir)

// Cleanup: drop the reference when the screen goes away
```

**Flutter**

```dart
// Progress
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'embed') return;
  print('[embed] ${event['phase']} ${((event['progress'] ?? 0) * 100).round()}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'embed',
  engines_path: 'TheStageAI/embeddinggemma-2',
);

// Cleanup
await TheStageFlutterSDK.stop_model(model_name: 'embed');
```

Phases: `downloading` → `extracting` → `loading` → `ready`. Cache
hits skip the first two. Flutter loads every input kind; on Swift,
`modalities` makes the first load shorter. Full contract:
[Get started](./README.md) (**Load Progress**).
