# Páreme la mano — versión 1 (Flutter + Firebase)

Juego multijugador (2 a 8 jugadores), 5 rondas, 90 s por ronda, 6 categorías
al azar de 8, conteo automático de 10 s ("¡Páreme la mano!") cuando alguien
completa todo o se acaba el tiempo, y dashboard con puntaje de la ronda y
posiciones generales.

> Este código NO fue compilado ni probado todavía (aquí no hay Flutter SDK).
> Es muy probable que aparezcan errores menores en la primera compilación.

## Qué necesitas
- Una cuenta de Google (Firebase es gratis al inicio).
- Flutter instalado en un computador, o un servicio de compilación en la nube
  (Codemagic) que compile desde un repositorio de GitHub.

## Pasos
1. En una carpeta vacía: `flutter create --org com.tuempresa --project-name pareme_la_mano .`
2. Copia `pubspec.yaml` y la carpeta `lib/` de este proyecto encima de lo generado.
3. Crea un proyecto en https://console.firebase.google.com y agrega una app
   Android con el mismo nombre de paquete (`com.tuempresa.pareme_la_mano`).
4. Descarga `google-services.json` y colócalo en `android/app/`.
5. En Firebase activa:
   - Authentication → método de acceso **Anónimo**.
   - Firestore Database (modo producción) y pega el contenido de
     `firebase/firestore.rules` en la pestaña Reglas.
6. Configura Gradle para Firebase (plugin `com.google.gms.google-services`).
   La forma más fácil: ejecutar `flutterfire configure` o seguir
   https://firebase.google.com/docs/flutter/setup
7. En `android/app/src/main/AndroidManifest.xml`, dentro de `<activity ...>`,
   agrega `android:resizeableActivity="false"` (bloquea pantalla dividida).
8. Prueba: `flutter run` en dos dispositivos o emuladores.
9. Para publicar: `flutter build appbundle` y sube el `.aab` a Google Play Console.

## Anti-trampa incluido
- Si la app pasa a segundo plano durante la ronda, esa ronda vale 0.
- Pantalla dividida bloqueada (paso 7).
- Tiempo corto de ronda.

## Limitaciones de esta versión
- El reloj y el cálculo de puntajes los maneja el **anfitrión**; si el anfitrión
  cierra la app en pleno conteo, la partida se detiene. Solución futura:
  Cloud Functions (servidor).
- Los relojes de los celulares pueden diferir unos segundos entre sí.
- No hay voto entre jugadores para rechazar palabras falsas: acepta cualquier
  palabra de 2+ letras que empiece con la letra de la ronda.
- Sin anuncios todavía (AdMob se agrega después, con tus IDs de cuenta).

## Próximos pasos
1. Voto entre jugadores para validar palabras.
2. AdMob (anuncios con recompensa) y compra "quitar anuncios".
3. Pulir el Cuarenta (ver abajo).

## Cuarenta (sin conexión, contra bots)
Archivos: `lib/cuarenta/engine.dart` (reglas), `bot.dart` (bot), `cuarenta_page.dart` (pantallas).
Modos: tú contra 1 bot, o en parejas (tú + compañero bot contra 2 bots).
Formato: chica (a 40) o grande (mejor de 3 chicas).
Las reglas numéricas están como constantes al inicio de `engine.dart`.

Reglas implementadas (según lo que indicó César):
- 40 cartas (52 sin 8, 9, 10). 5 cartas por jugador; se reparte desde la izquierda y juega primero el de la derecha del repartidor.
- Levantar por pareo, por suma de DOS cartas de la mesa y por escalera automática.
- Trío de entrada 2, caída 2, limpia 2, caída y limpia juntas 2, cuatro iguales de entrada 10.
- Cartón: 20 cartas = 6 puntos, +1 por carta extra, impar sube al par. Menos de 20: sin puntos.
- Con 30 puntos o más ya no se cobra cartón.

Supuestos míos (verificar):
- "Cuatro cartas pasa la mano con 10 a favor" lo implementé como +10 puntos al equipo.
- Con 20 cartas cada equipo, el cartón (6) lo cobra el equipo que no reparte.
- La escalera siempre se levanta (no hay penalización por omitirla).
- Las rondas siguen cobrándose después de 30 puntos (solo el cartón se bloquea).
- No existe la regla de los 38 puntos.
- "Grande" = al mejor de 3 chicas.
