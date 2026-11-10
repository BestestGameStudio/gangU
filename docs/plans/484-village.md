# Abandoned village (#484)

Work in progress. One fixed southern overworld village, dense trees and a single east-west road. Entering starts the existing location-event pipeline and spawns 30 mustache men around the village. Leaving ends the encounter without the clear reward. Killing all of them drops coins through the existing RewardDrop route.

Implementation, visual demo and independent review pending. No tests created, edited or run. Existing test365 has a known stale assertion that the production overworld places no location triggers; this feature intentionally changes that assumption.
