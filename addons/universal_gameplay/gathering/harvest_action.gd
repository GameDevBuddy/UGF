class_name HarvestAction
extends InteractionAction
## Works a resource node. The bridge between "press E on the tree" and
## gathering.
##
## An [InteractionAction], so a tree is chopped through exactly the pipeline a
## door is opened with -- and a timed harvest is
## [member InteractionDefinition.duration], not a second timer beside it.
##
## It lives in Gathering rather than in Interaction because that is the
## direction that keeps both removable (rule 10).


func can_execute(context: InteractionContext) -> FrameworkResult:
	var node := _find_node(context)
	if node == null:
		return FrameworkResult.fail(
			&"harvest.no_node", "There is nothing to gather here."
		)
	return node.can_harvest(context.interactor)


func execute(context: InteractionContext) -> FrameworkResult:
	var node := _find_node(context)
	if node == null:
		return FrameworkResult.fail(
			&"harvest.no_node", "There is nothing to gather here."
		)
	return node.harvest(context.interactor)


func _find_node(context: InteractionContext) -> ResourceNode:
	if context == null or context.target == null:
		return null
	for component in DefinitionBinder.collect_components(context.target):
		if component is ResourceNode:
			return component as ResourceNode
	return null
