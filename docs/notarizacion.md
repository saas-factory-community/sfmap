# Notarización de Apple · pendiente del mantenedor

La release 0.3.0 está firmada con una identidad local estable (`SFMAP_IDENTITY`, por defecto «SFlow Dev»),
**sin Developer ID ni notarización**. Por eso macOS pide «Abrir de todos modos» la primera vez
(ver [instalacion.md](instalacion.md)). Quitar ese paso exige una acción del dueño de la cuenta Apple:

1. Inscribirse en el Apple Developer Program (99 USD/año) con la cuenta de la organización.
2. Crear un certificado **Developer ID Application** e instalarlo en el llavero de la Mac que empaqueta.
3. Crear una contraseña de app en appleid.apple.com y guardar el perfil de notarización:
   `xcrun notarytool store-credentials sfmap-notary --apple-id <correo> --team-id <TEAM> --password <app-password>`
4. Empaquetar con esa identidad y runtime endurecido:
   `SFMAP_IDENTITY="Developer ID Application: <Nombre> (<TEAM>)" bash scripts/package.sh --no-install`
   (añadir `--options runtime --timestamp` a `codesign` en `package.sh` cuando se active Developer ID).
5. Notarizar y engrapar:
   `ditto -c -k --keepParent dist/sfmap.app /tmp/sfmap.zip && xcrun notarytool submit /tmp/sfmap.zip --keychain-profile sfmap-notary --wait && xcrun stapler staple dist/sfmap.app`
6. Rehacer los assets con `bash scripts/release.sh`, verificar con `spctl -a -vv dist/sfmap.app`
   («source=Notarized Developer ID») y publicar una versión de parche.

Hasta entonces, la guía documenta el camino seguro para autorizar solo esta app.
