# Filmswipe

Proyecto Flutter Android que empaqueta el prototipo web de Filmswipe dentro de
una WebView local.

- `index.html`: app principal, con onboarding, swipe, filtros, busqueda,
  entradas, reservas, detalle y perfil.
- `lib/main.dart`: app Flutter que carga `index.html` como asset local.
- `brand.html`: HTML adjunto con marca, icono y logotipo.
- `MoviePoster.dc.html`: componente original adjunto para la direccion visual
  de posters.
- `support.js`: runtime original adjunto para los `.dc.html`.

Instalar en el movil Android:

```sh
cd "/Users/lucrezialafratta/Documents/Filmswipe"
flutter pub get
flutter run -d RFGL22F1XTY
```

Crear un APK debug:

```sh
cd "/Users/lucrezialafratta/Documents/Filmswipe"
flutter pub get
flutter build apk --debug --target-platform android-arm64
```

El APK queda en:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Servidor local para ver solo la version web:

```sh
python3 -m http.server 5173
```

Luego abre `http://127.0.0.1:5173/`.
