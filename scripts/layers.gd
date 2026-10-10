class_name Layers
## Physics layer bits shared by every system.

const WORLD := 1        ## Plane hull, ground, scenery.
const PLAYER := 2
const PROP := 4         ## Loose objects: luggage, crates, items, debris.
const NPC := 8          ## Passengers, crew, the captain.
const INTERACT := 32    ## Interactable Area3D volumes (see Interactable).
