;;;; translations.lisp — Littoral's own strings in French, German and Spanish
;;;;
;;;; Applications add their own strings with DEFINE-TRANSLATIONS or
;;;; LOAD-TRANSLATIONS; MISSING-TRANSLATIONS lists what a language still lacks.

(in-package #:littoral)

(define-translations "fr"
  ;; Dialogs
  ("OK" "OK") ("Yes" "Oui") ("No" "Non") ("Cancel" "Annuler") ("Continue" "Continuer")
  ("Answer" "Réponse") ("Choice" "Choix") ("Username" "Nom d'utilisateur") ("Password" "Mot de passe")
  ("Log in" "Se connecter") ("Close" "Fermer") ("Save" "Enregistrer") ("Create" "Créer")
  ("Your session expired, so you are starting again from the beginning."
   "Votre session a expiré : vous recommencez depuis le début.")
  ;; Widgets
  ("Pages" "Pages") ("« Previous" "« Précédent") ("Next »" "Suivant »") ("Tabs" "Onglets")
  ("Collapse" "Replier") ("Expand" "Déplier") ("Move up" "Monter") ("Move down" "Descendre")
  ("Move item ~D up" "Monter l'élément ~D") ("Move item ~D down" "Descendre l'élément ~D")
  ("Language" "Langue") ("Steps" "Étapes") ("Review" "Vérification") ("Change ~A" "Modifier ~A")
  ("Change" "Modifier") ("Finish" "Terminer") ("Next" "Suivant") ("Table" "Tableau") ("Actions" "Actions") ("Filter ~A" "Filtrer ~A") ("Filter" "Filtrer")
  ("Nothing matches." "Aucun résultat.") ("Edit" "Modifier") ("~D row" "~D ligne" "~D lignes") ("Data" "Données")
  ("Previous month" "Mois précédent") ("Next month" "Mois suivant") ("Move to ~A" "Déplacer vers ~A")
  ("Mon" "lun") ("Tue" "mar") ("Wed" "mer") ("Thu" "jeu") ("Fri" "ven") ("Sat" "sam") ("Sun" "dim")
  ("Markdown: **strong**, *emphasis*, `code`, [links](https://…), - lists, # headings."
   "Markdown : **gras**, *italique*, `code`, [liens](https://…), - listes, # titres.") ("Remove" "Supprimer")
  ("~A is too large: at most ~:D bytes." "~A est trop gros : au plus ~:D octets.")
  ("~A must be a PNG, JPEG, GIF or WebP image." "~A doit être une image PNG, JPEG, GIF ou WebP.")
  ("Waiting to start." "En attente.") ("Working… ~D%" "En cours… ~D %") ("Done." "Terminé.")
  ("Failed: ~A" "Échec : ~A") ("Cancelled." "Annulé.")
  ("Failed (~A); trying again in ~D s, attempt ~D of ~D." "Échec (~A) ; nouvel essai dans ~D s, essai ~D sur ~D.")
  ;; Validation
  ("required" "obligatoire")
  ("~A is required." "~A est obligatoire.")
  ("~A is not in the expected form." "~A n'a pas la forme attendue.")
  ("~A must be at most ~D characters." "~A doit faire au plus ~D caractères.")
  ("~A must be an email address." "~A doit être une adresse e-mail.")
  ("~A must be a web address starting http:// or https://."
   "~A doit être une adresse web commençant par http:// ou https://.")
  ("~A must be a whole number." "~A doit être un nombre entier.")
  ("~A must be at least ~D." "~A doit valoir au moins ~D.")
  ("~A must be at most ~D." "~A doit valoir au plus ~D.")
  ("~A is not one of the choices." "~A ne fait pas partie des choix.")
  ("~A must be a date, like 2026-10-06." "~A doit être une date, comme 2026-10-06.")
  ;; Signing in
  ("Keep me signed in" "Rester connecté")
  ("Sign in" "Se connecter") ("Name" "Nom") ("Email" "E-mail") ("Back" "Retour")
  ("Forgot your password?" "Mot de passe oublié ?")
  ("Sign in with ~A" "Se connecter avec ~A")
  ("Too many failed attempts; try again in a minute." "Trop d'essais infructueux ; réessayez dans une minute.")
  ("Unknown user or wrong password." "Utilisateur inconnu ou mot de passe erroné.")
  ("You don't have permission to see this." "Vous n'avez pas l'autorisation de voir ceci.")
  ("Please sign in to see this." "Connectez-vous pour voir ceci.")
  ("Reset your password" "Réinitialiser votre mot de passe")
  ("Choose a new password" "Choisissez un nouveau mot de passe")
  ("If that address belongs to an account, a link to choose a new password is on its way."
   "Si cette adresse correspond à un compte, un lien pour choisir un nouveau mot de passe vous a été envoyé.")
  ("Send me a link" "M'envoyer un lien") ("New password" "Nouveau mot de passe") ("Again" "Confirmation")
  ("Passwords need at least 8 characters." "Le mot de passe doit faire au moins 8 caractères.")
  ("The passwords differ." "Les mots de passe diffèrent.")
  ("Save and sign in" "Enregistrer et se connecter")
  ("That link has expired or been used. Ask for a new one." "Ce lien a expiré ou a déjà servi. Demandez-en un nouveau.")
  ("Signing in with that provider didn't work. Please try again."
   "La connexion avec ce fournisseur a échoué. Veuillez réessayer.")
  ("Someone asked to reset the password for ~A.~%~%~
To choose a new one, open:~%~A~A/reset?token=~A~%~%~
The link works once, for an hour.  If it wasn't you, ignore this mail."
   "Quelqu'un a demandé à réinitialiser le mot de passe de ~A.~%~%~
Pour en choisir un nouveau, ouvrez :~%~A~A/reset?token=~A~%~%~
Le lien ne sert qu'une fois, pendant une heure.  Si ce n'était pas vous, ignorez ce message.")
  ;; Admin
  ("Tables" "Tables") ("Any" "Tous") ("Back to the list" "Retour à la liste")
  ("This record no longer exists." "Cet enregistrement n'existe plus.")
  ("New ~A" "Nouveau : ~A") ("Edit ~A #~D" "Modifier ~A nº ~D")
  ("Saved ~A #~D." "~A nº ~D enregistré.") ("Created ~A #~D." "~A nº ~D créé.")
  ("Delete ~A #~D, ~A?" "Supprimer ~A nº ~D, ~A ?") ("Deleted ~A #~D." "~A nº ~D supprimé.")
  ("Someone else changed this record meanwhile; here it is as they left it."
   "Quelqu'un d'autre a modifié cet enregistrement entre-temps ; le voici tel qu'il l'a laissé."))

(define-translations "de"
  ;; Dialogs
  ("OK" "OK") ("Yes" "Ja") ("No" "Nein") ("Cancel" "Abbrechen") ("Continue" "Weiter")
  ("Answer" "Antwort") ("Choice" "Auswahl") ("Username" "Benutzername") ("Password" "Passwort")
  ("Log in" "Anmelden") ("Close" "Schließen") ("Save" "Speichern") ("Create" "Anlegen")
  ("Your session expired, so you are starting again from the beginning."
   "Ihre Sitzung ist abgelaufen, daher beginnen Sie wieder von vorn.")
  ;; Widgets
  ("Pages" "Seiten") ("« Previous" "« Zurück") ("Next »" "Weiter »") ("Tabs" "Reiter")
  ("Collapse" "Zuklappen") ("Expand" "Aufklappen") ("Move up" "Nach oben") ("Move down" "Nach unten")
  ("Move item ~D up" "Eintrag ~D nach oben") ("Move item ~D down" "Eintrag ~D nach unten")
  ("Language" "Sprache") ("Steps" "Schritte") ("Review" "Überprüfen") ("Change ~A" "~A ändern")
  ("Change" "Ändern") ("Finish" "Fertigstellen") ("Next" "Weiter") ("Table" "Tabelle") ("Actions" "Aktionen") ("Filter ~A" "~A filtern") ("Filter" "Filtern")
  ("Nothing matches." "Keine Treffer.") ("Edit" "Bearbeiten") ("~D row" "~D Zeile" "~D Zeilen") ("Data" "Daten")
  ("Previous month" "Voriger Monat") ("Next month" "Nächster Monat") ("Move to ~A" "Nach ~A verschieben")
  ("Mon" "Mo") ("Tue" "Di") ("Wed" "Mi") ("Thu" "Do") ("Fri" "Fr") ("Sat" "Sa") ("Sun" "So")
  ("Markdown: **strong**, *emphasis*, `code`, [links](https://…), - lists, # headings."
   "Markdown: **fett**, *kursiv*, `Code`, [Links](https://…), - Listen, # Überschriften.") ("Remove" "Entfernen")
  ("~A is too large: at most ~:D bytes." "~A ist zu groß: höchstens ~:D Bytes.")
  ("~A must be a PNG, JPEG, GIF or WebP image." "~A muss ein PNG-, JPEG-, GIF- oder WebP-Bild sein.")
  ("Waiting to start." "Wartet.") ("Working… ~D%" "In Arbeit… ~D %") ("Done." "Fertig.")
  ("Failed: ~A" "Fehlgeschlagen: ~A") ("Cancelled." "Abgebrochen.")
  ("Failed (~A); trying again in ~D s, attempt ~D of ~D." "Fehlgeschlagen (~A); neuer Versuch in ~D s, Versuch ~D von ~D.")
  ;; Validation
  ("required" "Pflichtfeld")
  ("~A is required." "~A ist erforderlich.")
  ("~A is not in the expected form." "~A hat nicht die erwartete Form.")
  ("~A must be at most ~D characters." "~A darf höchstens ~D Zeichen lang sein.")
  ("~A must be an email address." "~A muss eine E-Mail-Adresse sein.")
  ("~A must be a web address starting http:// or https://."
   "~A muss eine Webadresse sein, die mit http:// oder https:// beginnt.")
  ("~A must be a whole number." "~A muss eine ganze Zahl sein.")
  ("~A must be at least ~D." "~A muss mindestens ~D sein.")
  ("~A must be at most ~D." "~A darf höchstens ~D sein.")
  ("~A is not one of the choices." "~A ist keine der Möglichkeiten.")
  ("~A must be a date, like 2026-10-06." "~A muss ein Datum sein, etwa 2026-10-06.")
  ;; Signing in
  ("Keep me signed in" "Angemeldet bleiben")
  ("Sign in" "Anmelden") ("Name" "Name") ("Email" "E-Mail") ("Back" "Zurück")
  ("Forgot your password?" "Passwort vergessen?")
  ("Sign in with ~A" "Mit ~A anmelden")
  ("Too many failed attempts; try again in a minute." "Zu viele Fehlversuche; versuchen Sie es in einer Minute erneut.")
  ("Unknown user or wrong password." "Unbekannter Benutzer oder falsches Passwort.")
  ("You don't have permission to see this." "Sie dürfen dies nicht sehen.")
  ("Please sign in to see this." "Bitte melden Sie sich an, um dies zu sehen.")
  ("Reset your password" "Passwort zurücksetzen")
  ("Choose a new password" "Neues Passwort wählen")
  ("If that address belongs to an account, a link to choose a new password is on its way."
   "Falls diese Adresse zu einem Konto gehört, ist ein Link zum Wählen eines neuen Passworts unterwegs.")
  ("Send me a link" "Link senden") ("New password" "Neues Passwort") ("Again" "Wiederholen")
  ("Passwords need at least 8 characters." "Passwörter brauchen mindestens 8 Zeichen.")
  ("The passwords differ." "Die Passwörter stimmen nicht überein.")
  ("Save and sign in" "Speichern und anmelden")
  ("That link has expired or been used. Ask for a new one." "Dieser Link ist abgelaufen oder wurde schon benutzt. Fordern Sie einen neuen an.")
  ("Signing in with that provider didn't work. Please try again."
   "Die Anmeldung über diesen Anbieter hat nicht geklappt. Bitte versuchen Sie es erneut.")
  ("Someone asked to reset the password for ~A.~%~%~
To choose a new one, open:~%~A~A/reset?token=~A~%~%~
The link works once, for an hour.  If it wasn't you, ignore this mail."
   "Jemand möchte das Passwort für ~A zurücksetzen.~%~%~
Um ein neues zu wählen, öffnen Sie:~%~A~A/reset?token=~A~%~%~
Der Link funktioniert einmal, eine Stunde lang.  Falls Sie das nicht waren, ignorieren Sie diese Nachricht.")
  ;; Admin
  ("Tables" "Tabellen") ("Any" "Alle") ("Back to the list" "Zurück zur Liste")
  ("This record no longer exists." "Dieser Datensatz existiert nicht mehr.")
  ("New ~A" "Neu: ~A") ("Edit ~A #~D" "~A Nr. ~D bearbeiten")
  ("Saved ~A #~D." "~A Nr. ~D gespeichert.") ("Created ~A #~D." "~A Nr. ~D angelegt.")
  ("Delete ~A #~D, ~A?" "~A Nr. ~D, ~A löschen?") ("Deleted ~A #~D." "~A Nr. ~D gelöscht.")
  ("Someone else changed this record meanwhile; here it is as they left it."
   "Jemand anderes hat diesen Datensatz inzwischen geändert; hier ist er in dessen Fassung."))

(define-translations "es"
  ;; Dialogs
  ("OK" "Aceptar") ("Yes" "Sí") ("No" "No") ("Cancel" "Cancelar") ("Continue" "Continuar")
  ("Answer" "Respuesta") ("Choice" "Opción") ("Username" "Usuario") ("Password" "Contraseña")
  ("Log in" "Entrar") ("Close" "Cerrar") ("Save" "Guardar") ("Create" "Crear")
  ("Your session expired, so you are starting again from the beginning."
   "Su sesión ha caducado, así que empieza de nuevo desde el principio.")
  ;; Widgets
  ("Pages" "Páginas") ("« Previous" "« Anterior") ("Next »" "Siguiente »") ("Tabs" "Pestañas")
  ("Collapse" "Contraer") ("Expand" "Expandir") ("Move up" "Subir") ("Move down" "Bajar")
  ("Move item ~D up" "Subir el elemento ~D") ("Move item ~D down" "Bajar el elemento ~D")
  ("Language" "Idioma") ("Steps" "Pasos") ("Review" "Revisión") ("Change ~A" "Cambiar ~A")
  ("Change" "Cambiar") ("Finish" "Terminar") ("Next" "Siguiente") ("Table" "Tabla") ("Actions" "Acciones") ("Filter ~A" "Filtrar ~A") ("Filter" "Filtrar")
  ("Nothing matches." "Sin resultados.") ("Edit" "Editar") ("~D row" "~D fila" "~D filas") ("Data" "Datos")
  ("Previous month" "Mes anterior") ("Next month" "Mes siguiente") ("Move to ~A" "Mover a ~A")
  ("Mon" "lu") ("Tue" "ma") ("Wed" "mi") ("Thu" "ju") ("Fri" "vi") ("Sat" "sá") ("Sun" "do")
  ("Markdown: **strong**, *emphasis*, `code`, [links](https://…), - lists, # headings."
   "Markdown: **negrita**, *cursiva*, `código`, [enlaces](https://…), - listas, # títulos.") ("Remove" "Quitar")
  ("~A is too large: at most ~:D bytes." "~A es demasiado grande: como máximo ~:D bytes.")
  ("~A must be a PNG, JPEG, GIF or WebP image." "~A debe ser una imagen PNG, JPEG, GIF o WebP.")
  ("Waiting to start." "En espera.") ("Working… ~D%" "Trabajando… ~D %") ("Done." "Hecho.")
  ("Failed: ~A" "Error: ~A") ("Cancelled." "Cancelado.")
  ("Failed (~A); trying again in ~D s, attempt ~D of ~D." "Error (~A); se reintentará en ~D s, intento ~D de ~D.")
  ;; Validation
  ("required" "obligatorio")
  ("~A is required." "~A es obligatorio.")
  ("~A is not in the expected form." "~A no tiene la forma esperada.")
  ("~A must be at most ~D characters." "~A debe tener como máximo ~D caracteres.")
  ("~A must be an email address." "~A debe ser una dirección de correo.")
  ("~A must be a web address starting http:// or https://."
   "~A debe ser una dirección web que empiece por http:// o https://.")
  ("~A must be a whole number." "~A debe ser un número entero.")
  ("~A must be at least ~D." "~A debe ser como mínimo ~D.")
  ("~A must be at most ~D." "~A debe ser como máximo ~D.")
  ("~A is not one of the choices." "~A no es una de las opciones.")
  ("~A must be a date, like 2026-10-06." "~A debe ser una fecha, como 2026-10-06.")
  ;; Signing in
  ("Keep me signed in" "Mantener la sesión iniciada")
  ("Sign in" "Iniciar sesión") ("Name" "Nombre") ("Email" "Correo") ("Back" "Volver")
  ("Forgot your password?" "¿Ha olvidado su contraseña?")
  ("Sign in with ~A" "Iniciar sesión con ~A")
  ("Too many failed attempts; try again in a minute." "Demasiados intentos fallidos; inténtelo de nuevo en un minuto.")
  ("Unknown user or wrong password." "Usuario desconocido o contraseña incorrecta.")
  ("You don't have permission to see this." "No tiene permiso para ver esto.")
  ("Please sign in to see this." "Inicie sesión para ver esto.")
  ("Reset your password" "Restablecer la contraseña")
  ("Choose a new password" "Elija una contraseña nueva")
  ("If that address belongs to an account, a link to choose a new password is on its way."
   "Si esa dirección pertenece a una cuenta, le hemos enviado un enlace para elegir una contraseña nueva.")
  ("Send me a link" "Enviarme un enlace") ("New password" "Contraseña nueva") ("Again" "Repetir")
  ("Passwords need at least 8 characters." "La contraseña debe tener al menos 8 caracteres.")
  ("The passwords differ." "Las contraseñas no coinciden.")
  ("Save and sign in" "Guardar e iniciar sesión")
  ("That link has expired or been used. Ask for a new one." "Ese enlace ha caducado o ya se ha usado. Pida uno nuevo.")
  ("Signing in with that provider didn't work. Please try again."
   "No se pudo iniciar sesión con ese proveedor. Inténtelo de nuevo.")
  ("Someone asked to reset the password for ~A.~%~%~
To choose a new one, open:~%~A~A/reset?token=~A~%~%~
The link works once, for an hour.  If it wasn't you, ignore this mail."
   "Alguien ha pedido restablecer la contraseña de ~A.~%~%~
Para elegir una nueva, abra:~%~A~A/reset?token=~A~%~%~
El enlace sirve una vez, durante una hora.  Si no fue usted, ignore este correo.")
  ;; Admin
  ("Tables" "Tablas") ("Any" "Todos") ("Back to the list" "Volver a la lista")
  ("This record no longer exists." "Este registro ya no existe.")
  ("New ~A" "Nuevo: ~A") ("Edit ~A #~D" "Editar ~A n.º ~D")
  ("Saved ~A #~D." "~A n.º ~D guardado.") ("Created ~A #~D." "~A n.º ~D creado.")
  ("Delete ~A #~D, ~A?" "¿Borrar ~A n.º ~D, ~A?") ("Deleted ~A #~D." "~A n.º ~D borrado.")
  ("Someone else changed this record meanwhile; here it is as they left it."
   "Otra persona ha cambiado este registro mientras tanto; aquí está tal como lo dejó."))
