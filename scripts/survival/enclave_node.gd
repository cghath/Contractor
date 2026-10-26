class_name EnclaveNode
extends Node
## The enclave's node under the Survival autoload ("Survival/Enclave", added by FallenStory on
## the host when the world is set up): the hook the talk and trade lanes look for. The enclave's
## rules are Enclave's (static, over Survival.state()["enclave"]).

const NODE_NAME := "Enclave"


func _init() -> void:
	name = NODE_NAME


## Whether `rec` (a SurvivorPerson record) is the enclave's quartermaster (its trader: meds and
## fuel for food and people).
func is_quartermaster(rec: Dictionary) -> bool:
	return Enclave.is_quartermaster(rec)


## Host: makes sure the node is under Survival.
static func ensure() -> void:
	if Survival.get_node_or_null(NodePath(NODE_NAME)) == null:
		Survival.add_child(EnclaveNode.new())
