import 'package:flutter/widgets.dart';

/// Shows a text of the server's blueprint catalog (only in English) in the app's language;
/// what the app doesn't know, a plugin's blueprint for instance, stays as the server wrote it.
String blueprintText(BuildContext context, String english) => switch (Localizations.localeOf(context).languageCode) {
  'fr' => _fr[english] ?? english,
  _ => english,
};

/// The language agents made from a blueprint should write in (its prompt is English); null for English.
String? agentLanguage(BuildContext context) => switch (Localizations.localeOf(context).languageCode) {
  'fr' => 'French',
  _ => null,
};

/// Options of a weekdays slot when the server sends none (its presets).
const weekdayPresets = ['everyday', 'weekdays', 'weekends'];

const _fr = {
  // titles and descriptions
  'Morning briefing': 'Briefing du matin',
  "A short daily briefing: today's calendar, weather, and anything urgent waiting on you.":
      'Un court point quotidien : l’agenda du jour, la météo et ce qui t’attend d’urgent.',
  'Important-mail monitor': 'Veille des mails importants',
  'Check your inbox periodically and ping you ONLY about mail that actually needs attention.':
      'Surveille ta boîte mail et ne te prévient QUE pour les mails qui demandent vraiment ton attention.',
  'Weekly review': 'Bilan de la semaine',
  "A weekly recap: what got done, what's still open, and what's coming up.":
      'Un récap hebdo : ce qui est fait, ce qui reste ouvert et ce qui arrive.',
  'Workday start reminder': 'Début de journée',
  'A weekday nudge with your agenda and top priorities.': 'Un rappel en semaine avec ton agenda et tes priorités.',
  'Custom reminder': 'Rappel personnalisé',
  'A recurring reminder in your own words, on your schedule.': 'Un rappel récurrent, avec tes mots et à ton rythme.',
  'Evening wind-down': 'Fin de journée',
  "An end-of-day check-in: tomorrow's calendar at a glance and anything you should prep tonight.":
      'Un point du soir : l’agenda de demain en un coup d’œil et ce qu’il faut préparer ce soir.',
  'Topic news digest': 'Revue d’actu sur un sujet',
  'A recurring digest on a topic you care about — deduped against what was already sent, so only genuinely new items land.':
      'Une revue régulière sur un sujet qui t’intéresse, sans redites : seules les vraies nouveautés arrivent.',
  'Bills & renewals reminder': 'Factures et renouvellements',
  'A heads-up before a recurring payment, subscription renewal, or due date — so nothing auto-charges by surprise.':
      'Un avertissement avant un paiement récurrent, un renouvellement d’abonnement ou une échéance, pour éviter les prélèvements surprises.',
  'Price & availability watch': 'Veille de prix et de disponibilité',
  'Watch an exact product, flight, hotel, or listing and alert when your price or availability condition is met.':
      'Surveille un produit, un vol, un hôtel ou une annonce précise et te prévient quand ta condition de prix ou de disponibilité est remplie.',
  'Competitor news watch': 'Veille concurrentielle',
  'Track named companies for material news — launches, pricing, funding, filings — with a cited digest.':
      'Suit des entreprises précises (lancements, prix, levées de fonds, publications officielles) avec un résumé sourcé.',
  'Habit check-in': 'Suivi d’habitude',
  'A recurring nudge to keep a habit on track and reflect on whether you did it.':
      'Un rappel régulier pour tenir une habitude et faire le point sur ce que tu as fait.',
  'Hydration & movement nudge': 'Eau et mouvement',
  'A periodic nudge during the day to drink water, stand up, and stretch.':
      'Un rappel régulier dans la journée pour boire, te lever et t’étirer.',
  'Weekly meal plan': 'Menus de la semaine',
  'A weekly meal plan plus a consolidated grocery list, tuned to your diet and how much time you have to cook.':
      'Les menus de la semaine et la liste de courses, adaptés à ton régime et au temps que tu as pour cuisiner.',
  'Daily learning drip': 'Une leçon par jour',
  'One bite-sized lesson a day on a topic you want to learn, building progressively over time.':
      'Une petite leçon par jour sur un sujet que tu veux apprendre, de plus en plus poussée.',
  'Gratitude & reflection prompt': 'Gratitude et réflexion',
  'A gentle evening prompt to reflect on the day and note what went well.':
      'Une question douce le soir pour repenser à ta journée et noter ce qui s’est bien passé.',
  'On-this-day discovery': 'La découverte du jour',
  'A daily dose of curiosity: a notable historical event, fact, or word for the day.':
      'Ta dose de curiosité quotidienne : un événement historique, un fait ou un mot du jour.',
  // field labels and help
  'What time?': 'À quelle heure ?',
  '24h local time, e.g. 08:00': 'Heure locale sur 24 h, par exemple 08:00',
  'Where to deliver?': 'Où l’envoyer ?',
  'origin = the chat you set this up from (or your configured home channel when created from the dashboard); local = save only, no message; or any connected platform name':
      'Origine = ton canal principal ; Local = enregistré sans message ; ou le nom d’une plateforme connectée',
  'How often?': 'À quelle fréquence ?',
  'minutes between checks': 'minutes entre deux vérifications',
  'Only notify me if the mail…': 'Ne me prévenir que si le mail…',
  'Which day?': 'Quel jour ?',
  'Remind me to…': 'Me rappeler de…',
  'Repeat on': 'Répéter',
  'What topic?': 'Quel sujet ?',
  'a subject, product, person, or search phrase': 'un sujet, un produit, une personne ou une recherche',
  'How many bullets?': 'Combien de points ?',
  "What's due?": 'Qu’est-ce qui arrive à échéance ?',
  'What exactly to watch?': 'Que surveiller exactement ?',
  'URL or precise description — variant, dates, seller': 'Lien ou description précise : variante, dates, vendeur',
  'Alert me when…': 'Me prévenir quand…',
  'threshold price (state the currency), availability, or terms change':
      'un prix seuil (précise la devise), une disponibilité ou un changement de conditions',
  'hours between checks — be gentle with rate limits': 'heures entre deux vérifications (sans abuser des sites)',
  'Which companies?': 'Quelles entreprises ?',
  'canonical names and domains; aliases help dedup': 'noms et sites officiels ; les alias aident à éviter les doublons',
  'Which events matter?': 'Quels événements comptent ?',
  'Which habit?': 'Quelle habitude ?',
  'hours between nudges': 'heures entre deux rappels',
  'Start hour': 'Heure de début',
  'first hour of the active window (24h)': 'première heure de la plage active (24 h)',
  'End hour': 'Heure de fin',
  'last hour of the active window (24h)': 'dernière heure de la plage active (24 h)',
  'Diet?': 'Régime ?',
  'Meals per day?': 'Repas par jour ?',
  'Cooking effort?': 'Temps de cuisine ?',
  'Learn about…': 'Apprendre…',
  'What kind?': 'Quel genre ?',
  // example values of the text fields
  'product launches, pricing changes, funding, partnerships, executive moves, incidents':
      'lancements de produits, changements de prix, levées de fonds, partenariats, changements de direction, incidents',
  'two or three competitors, by canonical name': 'deux ou trois concurrents, par leur nom officiel',
  'the all-in price drops below my target': 'le prix tout compris passe sous mon objectif',
  'needs a reply today, is from my manager or family, or mentions a deadline':
      'demande une réponse aujourd’hui, vient de mon manager ou de ma famille, ou parle d’une échéance',
  '20 minutes of reading': '20 minutes de lecture',
  'a product URL or exact flight/hotel/listing description':
      'le lien d’un produit ou la description exacte d’un vol, d’un hôtel ou d’une annonce',
  'AI and technology': 'IA et technologie',
  'Spanish vocabulary': 'Vocabulaire espagnol',
  'my streaming subscription renews soon': 'mon abonnement de streaming se renouvelle bientôt',
  'take a break and stretch': 'faire une pause et m’étirer',
  // option values (only their display; the server gets the original)
  'origin': 'Origine',
  'local': 'Local (sans message)',
  'email': 'E-mail',
  'everyday': 'Tous les jours',
  'weekdays': 'En semaine',
  'weekends': 'Le week-end',
  'sunday': 'Dimanche',
  'monday': 'Lundi',
  'friday': 'Vendredi',
  'saturday': 'Samedi',
  'no restrictions': 'Sans restriction',
  'vegetarian': 'Végétarien',
  'vegan': 'Végan',
  'high-protein': 'Riche en protéines',
  'low-carb': 'Pauvre en glucides',
  'dinner only': 'Dîner seulement',
  'lunch and dinner': 'Déjeuner et dîner',
  'all three': 'Les trois',
  'quick': 'Rapide',
  'medium': 'Moyen',
  'ambitious': 'Ambitieux',
  'on this day in history': 'Ce jour-là dans l’histoire',
  'word of the day': 'Le mot du jour',
  'science fact': 'Un fait scientifique',
  'quote of the day': 'La citation du jour',
};
