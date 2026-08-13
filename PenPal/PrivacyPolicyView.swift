//
//  Untitled.swift
//  TravelingFriends
//
//  Created by Emily on 02/06/2026.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                Text(appText("Privacy Policy", languageRaw))
                    .font(.largeTitle.bold())

                Text(privacyBody)
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Privacy", languageRaw))
    }

    private var privacyBody: String {
        switch AppLanguage(rawValue: languageRaw) ?? .english {
        case .english:
            return """
Last updated: June 2026

PenPal collects and stores the information necessary to provide the service.

Information we collect:
• Email address
• Username
• Profile information
• Group memberships
• Friend connections
• Magazines and uploaded images

How we use information:
• To create and manage your account
• To allow users to connect with friends
• To publish and share magazines
• To improve app functionality

We do not sell personal information.

Your data is stored securely using Firebase services provided by Google.

You can permanently delete your account at any time from Settings. Deleting your account removes your profile and associated content.

If you have questions regarding privacy, contact:
support@penpal-app.com
"""
        case .german:
            return """
Zuletzt aktualisiert: Juni 2026

PenPal sammelt und speichert die Informationen, die notwendig sind, um den Dienst bereitzustellen.

Informationen, die wir sammeln:
• E-Mail-Adresse
• Benutzername
• Profilinformationen
• Gruppenmitgliedschaften
• Freundschaften
• Magazine und hochgeladene Bilder

Wie wir Informationen verwenden:
• Um dein Konto zu erstellen und zu verwalten
• Damit Nutzer sich mit Freunden verbinden können
• Um Magazine zu veröffentlichen und zu teilen
• Um die App-Funktionalität zu verbessern

Wir verkaufen keine personenbezogenen Daten.

Deine Daten werden sicher über Firebase-Dienste von Google gespeichert.

Du kannst dein Konto jederzeit dauerhaft in den Einstellungen löschen. Das Löschen deines Kontos entfernt dein Profil und die zugehörigen Inhalte.

Bei Fragen zum Datenschutz:
support@penpal-app.com
"""
        case .italian:
            return """
Ultimo aggiornamento: giugno 2026

PenPal raccoglie e conserva solo le informazioni necessarie a offrire il servizio.

Informazioni che raccogliamo:
• Indirizzo e-mail
• Nome utente
• Informazioni del profilo
• Appartenenze ai gruppi
• Collegamenti di amicizia
• Magazine e immagini caricate

Come usiamo le informazioni:
• Per creare e gestire il tuo account
• Per permettere agli utenti di restare in contatto con gli amici
• Per pubblicare e condividere magazine
• Per migliorare il funzionamento dell’app

Non vendiamo dati personali.

I tuoi dati sono conservati in modo sicuro tramite i servizi Firebase forniti da Google.

Puoi eliminare definitivamente il tuo account in qualsiasi momento dalle Impostazioni. L’eliminazione rimuove il profilo e i contenuti associati.

Per domande sulla privacy:
support@penpal-app.com
"""
        case .spanish:
            return """
Última actualización: junio de 2026

PenPal recopila y almacena la información necesaria para ofrecer el servicio.

Información que recopilamos:
• Dirección de email
• Usuario
• Información del perfil
• Membresías de grupos
• Conexiones de amistad
• Revistas e imágenes subidas

Cómo usamos la información:
• Para crear y gestionar tu cuenta
• Para permitir que los usuarios conecten con amigos
• Para publicar y compartir revistas
• Para mejorar la funcionalidad de la app

No vendemos información personal.

Tus datos se almacenan de forma segura mediante servicios Firebase proporcionados por Google.

Puedes eliminar permanentemente tu cuenta en cualquier momento desde Ajustes. Al eliminarla se eliminan tu perfil y el contenido asociado.

Si tienes preguntas sobre privacidad:
support@penpal-app.com
"""
        case .french:
            return """
Dernière mise à jour : juin 2026

PenPal collecte et stocke les informations nécessaires pour fournir le service.

Informations collectées :
• Adresse e-mail
• Nom d’utilisateur
• Informations de profil
• Appartenance aux groupes
• Connexions d’amitié
• Magazines et images importées

Comment nous utilisons les informations :
• Pour créer et gérer ton compte
• Pour permettre aux utilisateurs de se connecter avec des amis
• Pour publier et partager des magazines
• Pour améliorer le fonctionnement de l’app

Nous ne vendons pas les informations personnelles.

Tes données sont stockées de manière sécurisée avec les services Firebase fournis par Google.

Tu peux supprimer définitivement ton compte à tout moment depuis les Réglages. La suppression retire ton profil et le contenu associé.

Pour toute question sur la confidentialité :
support@penpal-app.com
"""
        }
    }
}
