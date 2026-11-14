extends Node

var BoardSaveSence 


func Switch_to_minigame(minigame:String):
	#Called to change to new Sceen
	var TheRoot = get_node("/root")  #need this as get_node will stop work once you remove your self from the Tree
	var BoardSence = get_tree().get_first_node_in_group("GameBoard")
	BoardSaveSence = BoardSence  #variable in Autoload script
	#print(ThisScene)
	#ThisScene.print_tree()
	TheRoot.remove_child(BoardSence)
	
	var NextScene = load(minigame).instantiate()
	TheRoot.add_child(NextScene)

func Back_to_board():
	var TheRoot = get_node("/root")  #need this as get_node will stop work once you remove your self from the Tree
	var ThisScene = get_node("/root/MainMenu")
	
	TheRoot.remove_child(ThisScene)
	ThisScene.queue_free()
	
	if BoardSaveSence == null: breakpoint
	TheRoot.add_child(BoardSaveSence)
