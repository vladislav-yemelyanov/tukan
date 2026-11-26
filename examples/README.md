# Tukan Multi-Platform Examples

End-to-end runnable workspace showing Tukan code generation, `tukan` for TypeScript (Next.js + Bun), and `tukan` for Dart (Flutter + FVM) sharing the same local OpenAPI Todo backend.

## Layout

- [backend/](backend/) — Bun + TypeScript API server (`http://localhost:4000`) serving OpenAPI 3.0.3 at `/openapi/todos.json` and implementing auth-free Todos CRUD.
- [tukan.json5](tukan.json5) — Tukan configuration generating TypeScript (`nextjs-app/src/generated/todos.ts`) and Dart (`flutter-app/lib/generated/todos.dart`) models and operation bindings from the local backend.
- [generate.sh](generate.sh) — Builds Tukan from `core/` and regenerates all models/paths from the local backend.
- [nextjs-app/](nextjs-app/) — Next.js + Bun frontend wrapping `tukan` inside [`src/services`](nextjs-app/src/services/index.ts) (`export const services = createServices()`).
- [flutter-app/](flutter-app/) — Flutter app pinned via FVM (`.fvmrc` -> `stable`) wrapping `tukan` inside [`lib/services`](flutter-app/lib/services/services.dart) (`final AppServices services = AppServices.create()`).

## Quick Start

1. **Start the OpenAPI backend**:

   ```sh
   cd examples/backend
   bun install
   bun run dev
   ```

2. **Regenerate TypeScript and Dart APIs with Tukan**:

   ```sh
   bash examples/generate.sh
   ```

3. **Run the Next.js app (Bun)**:

   ```sh
   cd clients/ts && tsc -p tsconfig.json
   cd ../../examples/nextjs-app
   bun install
   bun run dev
   ```

   Open `http://localhost:3000`.

4. **Run the Flutter app (FVM)**:

   ```sh
   cd examples/flutter-app
   fvm flutter pub get
   fvm flutter run -d macos
   ```

   Pass `--dart-define=API_BASE_URL=http://10.0.2.2:4000` on Android emulator if needed.
