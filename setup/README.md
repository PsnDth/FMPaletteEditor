# Palette Setup

Should already include all basecast characters with labelled colour names. Note that the stage will attempt to update projectiles when possible.

Some notes:

1. Octodad airdash reuses his eye white colour when regenerating his clothes. The banana on dash attack is not mapped
2. CV - several attacks are not mapped: 
    a. Forward aerial - laser/visor
    b. Down smash - everything except outline
    c. Up smash - laser/visor
    d. Down special - everything
    e. Neutral special - everything except outline
3. Welltaro
    a. All fire effects/projectiles (incl. bullets) are not mapped
    b. Outlines are not replace-able? Need to double check
    c. Sketch animations have weird mapping (obv)
4. Orcane 
    a. Everything is mapped
    b. Bubbles (from downb/forward air) are* mapped but not present in hud image. They are separate for each costume so can be updated
5. Fishbunjin
    a. Effects are not mapped (downb/neutralb)
    b. Dumbbell is* mapped but not present in hud image. There is only 1 costume for it so all costumes will use the last updated colour
6. Watcher
    a. Wrath is implemented as a dynamic palette change so all wrath colour trails/eye changes will not apply in-game while in wrath. Divinity changes only work fully if done from calm, not wrath. This does not apply to neutralb though (and thus not the assist either)
    b. Effects for upb/sideb/usmash/taunt are spawned separately so cannot be mapped
