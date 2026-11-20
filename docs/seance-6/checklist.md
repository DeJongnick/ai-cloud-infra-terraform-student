# Checklist de préparation opérationnelle — team3

Une ligne sans preuve est un non. Un non est une réponse recevable : écrivez alors ce qui manque.

| Ligne | Question | Oui / non | Preuve | Ce qui manque |
| --- | --- | --- | --- | --- |
| Validated | Le modèle a-t-il été validé avant de recevoir du trafic, sur des segments et en ombre ? | Oui | `validation.txt` : contrat valide à 20 features ; écart AP +0,0206, IC95 [0,0158 ; 0,0251] ; segment le plus faible +0,0082 ; désaccord en ombre 4,34 %, écart d'alertes −1,83 point. | — |
| Reversible | Peut-on revenir en arrière par une commande écrite d'avance, et l'a-t-on vérifié par la mesure ? | Oui | Critères et commandes dans `mesures.md` ; retour exécuté vers `candidate=100` ; après 3 min : 1 751 transactions distinctes, 0 % d'erreur, p95 2,1 ms, âge 0 s. | — |
| Observed | Voit-on, par révision, les signaux qui disent que le service va mal ? | Oui | Référence étape 0 et mesures par révision ; `next` détectée à 100 % d'erreurs (> 5 %) en 2 min 48 s ; âge maximal 26 s. | Ajouter l'alerte automatique par révision proposée dans le post-mortem ; p95 et alertes ne sont pas mesurables quand aucun score ne réussit. |
| Degradable | Sait-on ce que fait le service quand la lecture de ses features échoue, et l'a-t-on choisi ? | Non | Aucun essai documenté avec `DEGRADED_POLICY=allow` ou `block`. | Tester les deux replis et choisir la politique en fonction de leurs coûts. |
| Restorable | Peut-on reconstruire le service à l'identique (modèle, agrégats, configuration) ? | Non | Pas de `plan.txt`, `infra/release.tf` ni `infra/scorer/` dans la copie ; `docs/seance-6/release.tf` est un squelette et n'a pas été appliqué. | Produire et vérifier le plan Terraform et les fichiers d'infrastructure attendus, sans appliquer de changement au service partagé. |
| Owned | Chaque élément a-t-il un responsable et une politique de réentraînement ? | Non | Aucune politique de réentraînement ni attribution de responsables n'est consignée dans les livrables de cette séance. | Définir la politique et désigner les responsables des modèles, données, alertes et retours arrière. |
