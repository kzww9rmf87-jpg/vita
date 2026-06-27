"""
Agent Nutrition — Analyse l'alimentation, détecte carences et risques,
calcule l'adhérence au plan.
"""
from typing import Optional
from models import AgentSignal, UserContext


def analyze(ctx: UserContext) -> Optional[AgentSignal]:
    nutrition_week = ctx.nutrition_week or []
    if not nutrition_week:
        return None

    snapshot = ctx.snapshot or {}
    weight_kg = float(snapshot.get("weight_kg") or 75)

    signals: list[AgentSignal] = []

    binge_risk = _detect_binge_risk(nutrition_week, weight_kg)
    if binge_risk:
        signals.append(binge_risk)

    protein_deficit = _detect_protein_deficit(nutrition_week, weight_kg)
    if protein_deficit:
        signals.append(protein_deficit)

    alcohol = _detect_alcohol_pattern(nutrition_week)
    if alcohol:
        signals.append(alcohol)

    dehydration = _detect_dehydration(nutrition_week)
    if dehydration:
        signals.append(dehydration)

    if not signals:
        return None

    return max(signals, key=lambda s: s.urgency * s.confidence)


def _detect_binge_risk(entries: list[dict], weight_kg: float) -> Optional[AgentSignal]:
    """
    Risque de fringale si :
    - 2 jours consécutifs en déficit > 20%
    - ET protéines < 1.4g/kg
    """
    if len(entries) < 2:
        return None

    tdee = _estimate_tdee(weight_kg)
    deficit_threshold = tdee * 0.80
    protein_target = weight_kg * 1.4

    days_in_deficit = 0
    low_protein_days = 0

    for entry in entries[-3:]:
        cals = entry.get("calories") or 0
        protein = float(entry.get("protein_g") or 0)

        if cals > 0 and cals < deficit_threshold:
            days_in_deficit += 1
        if cals > 0 and protein < protein_target:
            low_protein_days += 1

    if days_in_deficit < 2:
        return None

    confidence = 0.6 + (0.2 if low_protein_days >= 2 else 0)

    return AgentSignal(
        agent="nutrition",
        signal_type="binge_risk",
        description=f"{days_in_deficit} jours consécutifs en fort déficit calorique. "
                    "Les protéines basses augmentent le risque de fringales.",
        confidence=confidence,
        urgency=0.7,
        impact=0.75,
        data={"days_in_deficit": days_in_deficit, "low_protein_days": low_protein_days},
    )


def _detect_protein_deficit(entries: list[dict], weight_kg: float) -> Optional[AgentSignal]:
    """Protéines < 1.6g/kg sur la semaine."""
    protein_values = [
        float(e.get("protein_g") or 0)
        for e in entries
        if (e.get("protein_g") or 0) > 0
    ]
    if not protein_values:
        return None

    avg_protein = sum(protein_values) / len(protein_values)
    target = weight_kg * 1.6

    if avg_protein >= target * 0.9:
        return None

    gap = target - avg_protein

    return AgentSignal(
        agent="nutrition",
        signal_type="low_protein",
        description=f"Protéines moyennes : {avg_protein:.0f}g/j (cible : {target:.0f}g). "
                    f"Ajouter {gap:.0f}g aide la récupération musculaire.",
        confidence=0.85,
        urgency=0.5,
        impact=0.7,
        data={"avg_protein": avg_protein, "target": target, "gap": gap},
    )


def _detect_alcohol_pattern(entries: list[dict]) -> Optional[AgentSignal]:
    """≥ 3 jours avec alcool sur 7 jours → pattern signalé."""
    alcohol_days = sum(
        1 for e in entries if float(e.get("alcohol_g") or 0) > 5
    )
    if alcohol_days < 3:
        return None

    return AgentSignal(
        agent="nutrition",
        signal_type="alcohol_pattern",
        description=f"Tu as consommé de l'alcool {alcohol_days} jours cette semaine. "
                    "Cela peut perturber la récupération et le sommeil.",
        confidence=0.95,
        urgency=0.55,
        impact=0.6,
        data={"alcohol_days": alcohol_days},
    )


def _detect_dehydration(entries: list[dict]) -> Optional[AgentSignal]:
    water_values = [e.get("water_ml") for e in entries if e.get("water_ml")]
    if not water_values:
        return None

    avg_water = sum(water_values) / len(water_values)
    if avg_water >= 1500:
        return None

    return AgentSignal(
        agent="nutrition",
        signal_type="dehydration_risk",
        description=f"Hydratation moyenne : {avg_water:.0f}ml/j (minimum recommandé : 1500ml). "
                    "La déshydratation réduit les performances de 10 à 20%.",
        confidence=0.8,
        urgency=0.45,
        impact=0.55,
        data={"avg_water_ml": avg_water},
    )


def _estimate_tdee(weight_kg: float, activity_level: int = 3) -> float:
    """Harris-Benedict + facteur d'activité simplifié."""
    bmr = 10 * weight_kg + 625
    activity_multipliers = {1: 1.2, 2: 1.375, 3: 1.55, 4: 1.725, 5: 1.9}
    return bmr * activity_multipliers.get(activity_level, 1.55)
