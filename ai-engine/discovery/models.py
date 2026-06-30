"""Modèles Pydantic — Discovery Engine."""
from __future__ import annotations
from typing import Any, Optional
from pydantic import BaseModel, Field


class DiscoveryExchange(BaseModel):
    role: str          # 'vita' | 'user'
    content: str


class DiscoverySynthesis(BaseModel):
    """Synthèse générée par VITA après l'entretien."""
    rapport_au_sport:       Optional[str]    = None
    motivations:            list[str]        = Field(default_factory=list)
    freins:                 list[str]        = Field(default_factory=list)
    experiences_positives:  list[str]        = Field(default_factory=list)
    experiences_negatives:  list[str]        = Field(default_factory=list)
    contexte_prefere:       list[str]        = Field(default_factory=list)
    contraintes:            list[str]        = Field(default_factory=list)
    personnalite:           Optional[str]    = None
    resume_valide:          Optional[str]    = None  # texte de reformulation (affiché à l'utilisateur)


class ActivityProposal(BaseModel):
    """Une activité proposée par VITA à l'issue de l'entretien."""
    name:             str
    why_it_fits:      str    # justification ancrée dans la conversation
    first_step:       str    # première étape très concrète
    frequency:        str    # fréquence suggérée douce
    constraint_level: str    # tres_faible | faible | modere | eleve


# ── Inputs / Outputs des endpoints AI ─────────────────────────────────────────

class DiscoveryStartInput(BaseModel):
    user_id: str
    domain:  str = "sport"


class DiscoveryStartOutput(BaseModel):
    vita_opening: str
    already_started: bool = False


class DiscoveryMessageInput(BaseModel):
    user_id:      str
    domain:       str           = "sport"
    exchanges:    list[DiscoveryExchange]  # historique complet jusqu'ici
    user_message: str
    status:       str           = "discovering"    # état courant


class DiscoveryMessageOutput(BaseModel):
    vita_response:  str
    new_status:     str     # discovering | reformulating | proposing | completed
    synthesis:      Optional[DiscoverySynthesis] = None   # présent si new_status = reformulating
    proposals:      list[ActivityProposal]        = Field(default_factory=list)  # si new_status = proposing


class DiscoveryReactInput(BaseModel):
    user_id:             str
    domain:              str                = "sport"
    proposals:           list[ActivityProposal]
    accepted_names:      list[str]          = Field(default_factory=list)
    refused_names:       list[str]          = Field(default_factory=list)
    synthesis:           Optional[DiscoverySynthesis] = None


class DiscoveryReactOutput(BaseModel):
    vita_response:  str
    new_proposals:  list[ActivityProposal] = Field(default_factory=list)
    is_complete:    bool = False
