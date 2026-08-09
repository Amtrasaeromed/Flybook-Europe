# Build Fix v1.38.11

- Behebt den Xcode-Compilerfehler `Generic parameter 'ElementOfResult' could not be inferred` in `StudioModel.loadDestinations()`.
- Der Rückgabetyp des `compactMap` ist nun explizit als `StudioDestination?` deklariert.
- Die geladene Sammlung ist explizit als `[StudioDestination]` typisiert.
