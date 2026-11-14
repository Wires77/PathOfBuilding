-- Class mappings from the 3.30.0.1.4 client essence table.
local one="AilmentDoubleDamageEssence1"
local two="AilmentDoubleDamageTwoHandEssence1"
return {
	Amulet="AilmentDurationIfNotAppliedThatAilmentRecentlyEssence1",
	Belt="MagicFlaskEffectNoAdjacentFlasksEssence1",
	["Body Armour"]="GlobalDefencesNoOtherDefenceModifiersOnEquipmentEssence1",
	Boots="MovementSpeedPerNearbyEnemyEssence1",Gloves="AttackCastSpeedPerNearbyEnemyEssence1",
	Helmet="LocalGemLevelIfOnlySocketedGemEssence1",Quiver="ProjectilesChainAtCloseRangeEssence1",
	Ring="ShockwaveUnleashCountEssence1",Shield="ArmourAppliesElementalHitsIfBlockedRecentlyEssence1",
	Claw=one,Dagger=one,Wand=one,Sceptre=one,["One Handed Axe"]=one,["One Handed Mace"]=one,
	["One Handed Sword"]=one,["Thrusting One Handed Sword"]=one,
	Bow=two,Staff=two,["Two Handed Axe"]=two,["Two Handed Mace"]=two,["Two Handed Sword"]=two,
}
