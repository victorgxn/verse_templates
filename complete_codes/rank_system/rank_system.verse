using { /Fortnite.com/UI }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /Verse.org/Assets }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { AllRanks }

var PlayerStatsMap : weak_map(player, CustomPlayer) = map{}

CustomPlayer := class<persistable><final>():
    PlayerKills : int = 0
    PlayerDeaths : int = 0
    PlayerPoints : int = 0
    PlayerRank : int = 0


UpdatePlayerStats<constructor>(PlayerKills : int, PlayerDeaths:int, PlayerPoints:int, PlayerRank:int):= CustomPlayer:
    PlayerKills := PlayerKills
    PlayerDeaths := PlayerDeaths
    PlayerPoints := PlayerPoints
    PlayerRank := PlayerRank

RankManager := class(creative_device):
    @editable PlayerSpawners : []player_spawner_device = array{}
    @editable ElimManager : elimination_manager_device = elimination_manager_device{}
    @editable GuardSpawner : guard_spawner_device = guard_spawner_device{}
    @editable PointsPerKill : int = 5
    @editable MinusPointsPerDeath : int = 3
    @editable Settings : RankSettings = RankSettings{}
    
    var Players : []player = array{}

    OnBegin<override>()<suspends>:void=
        set Players = GetPlayspace().GetPlayers()
        InitPlayerManager()
        InitUI()
        Init()
        ElimManager.EliminatedEvent.Subscribe(OnPlayerSpawn)
        ElimManager.EliminationEvent.Subscribe(MaybePlayerSpawn)
        for ( PlayerSpawner : PlayerSpawners): 
            PlayerSpawner.SpawnedEvent.Subscribe(OnPlayerSpawn)
        
        spawn{GuardLoop()} 
        Update()

    InitPlayerManager():void=
        for(Player:Players):
            InitPlayerStats(Player)

    InitPlayerStats(Player:player):void=
        if(PlayerStatsMap[Player]):
            Print("Stats Exist")
        else:
            if(set PlayerStatsMap[Player] = CustomPlayer{}):
                Print("New Player stats were created")

    GetPlayerStats(Player:player):CustomPlayer = 
        PlayerStatsMap[Player] or CustomPlayer{}

    UpdateStats(Player:player, NewKills:int, NewDeaths:int, NewPoints:int, NewRank:int):CustomPlayer=
        UpdatedStats := UpdatePlayerStats(NewKills, NewDeaths, NewPoints, NewRank)
        if ( set PlayerStatsMap[Player] = UpdatedStats):
            Print("Updated player stats!")
            Print("Eliminations • {UpdatedStats.PlayerKills}")
            Print("Deaths • {UpdatedStats.PlayerDeaths}")
            Print("Points • {UpdatedStats.PlayerPoints}")
            Print("Rank • {UpdatedStats.PlayerRank}")
            
        return UpdatedStats
    

    Init():void=
        for(Player:Players):
            InitPlayerRank(Player)

    GuardLoop()<suspends> : void =
        loop:
            A := GuardSpawner.SpawnedEvent.Await()
            if ( F := A.GetFortCharacter[]):
                spawn{AwaitElimi(F)}


    OnPlayerSpawn(Agent:agent):void=
        if ( FortCharacter := Agent.GetFortCharacter[]):
            spawn{AwaitElimi(FortCharacter)}

    AwaitElimi(FortCharacter : fort_character)<suspends>: void=
        Result := FortCharacter.EliminatedEvent().Await()
        OnEliminaion(Result)

    MaybePlayerSpawn(MaybeAgent:?agent):void=
        if(Agent := MaybeAgent?):
            if ( FortCharacter := Agent.GetFortCharacter[]):
                spawn{AwaitElimi(FortCharacter)}

    Update()<suspends> : void=
        sync:
            loop:
                Player := GetPlayspace().PlayerAddedEvent().Await()
                if ( not Players.Find[Player]):
                    set Players += array{Player}
                    InitPlayerStats(Player)
                    InitPlayerUI(Player)
                    InitPlayerRank(Player)
            loop:
                Player := GetPlayspace().PlayerRemovedEvent().Await()
                set Players = for (CurrentPlayer : Players, CurrentPlayer <> Player) {CurrentPlayer}

    InitPlayerRank(Player:player):void=
        InitRankUI(Player, GetPlayerStats(Player),Settings)

    OnEliminaion(ElimResult : elimination_result):void=
        EliminatedCharacter := ElimResult.EliminatedCharacter
        MaybeEliminatingCharacter := ElimResult.EliminatingCharacter
        if(Player := player[EliminatedCharacter.GetAgent[]]):
            UpdateEliminatedPlayerStats(Player)

        if:
            EliminatingCharacter := MaybeEliminatingCharacter?
            EliminatingCharacter <> EliminatedCharacter
            Agent := EliminatingCharacter.GetAgent[]
            Player := player[Agent]
        then:
            UpdateEliminatingPlayerStats(Player)

    UpdateEliminatingPlayerStats(Player:player):void=
        PlayerStats := GetPlayerStats(Player)
        NewKills := PlayerStats.PlayerKills + 1
        NewDeaths := PlayerStats.PlayerDeaths
        NewPoints := PlayerStats.PlayerPoints + PointsPerKill
        NewRank := CountPlayerRankUp(PlayerStats, NewPoints)
        NewStats := UpdateStats(Player, NewKills, NewDeaths, NewPoints, NewRank)
        if ( NewStats.PlayerRank <> PlayerStats.PlayerRank):
            UpdateRank(Player, NewStats, Settings)
        else:
            UpdateProgress(Player, NewStats, Settings)

    UpdateEliminatedPlayerStats(Player:player):void=
        PlayerStats := GetPlayerStats(Player)
        NewPoints := PlayerStats.PlayerPoints - MinusPointsPerDeath >= 0 and PlayerStats.PlayerPoints - MinusPointsPerDeath or 0
        NewKills := PlayerStats.PlayerKills
        NewDeaths := PlayerStats.PlayerDeaths + 1
        NewRank := CountPlayerRankDown(PlayerStats, NewPoints)
        NewStats := UpdateStats(Player, NewKills, NewDeaths, NewPoints, NewRank)
        if ( NewStats.PlayerRank <> PlayerStats.PlayerRank):
            UpdateRank(Player, NewStats, Settings)
        else:
            UpdateProgress(Player, NewStats, Settings)

    CountPlayerRankUp(OldStats : CustomPlayer, NewPoints : int):int=
        CurrentRankIndex := OldStats.PlayerRank
        if( NextRank := Settings.RankTypes[CurrentRankIndex + 1]):
            if( NewPoints >= NextRank.PointsForRank):
                return CurrentRankIndex + 1
        return CurrentRankIndex

    CountPlayerRankDown(OldStats : CustomPlayer, NewPoints : int):int=
        CurrentRankIndex := OldStats.PlayerRank
        if(CurrentRank := Settings.RankTypes[CurrentRankIndex]):
            if( NewPoints < CurrentRank.PointsForRank):
                return CurrentRankIndex - 1
        CurrentRankIndex
    
    var PlayerWidgetsMap : [player]PlayerWidget = map{}

    InitUI():void=
        for ( Player : Players):
            InitPlayerUI(Player)

    InitPlayerUI(Player : player):void=
        Canvas : canvas = canvas{}
        ProgressBar : CustomProgressBar = CustomProgressBar:
            Width := 175.0
            Heigth := 19.0
        ProgressBar.Init()
        CanvasSlot := canvas_slot:
            Widget := ProgressBar.GetRootWidget()
            Anchors := anchors{Minimum := vector2{X:= 0.0, Y:= 1.0}, Maximum := vector2{X:=0.0, Y:=1.0}}
            Offsets := margin{Left:=45.0, Top := -421.0}
        Canvas.AddWidget(CanvasSlot)
        PlayerWidgets := PlayerWidget:
            Canvas := Canvas
            ProgressBar := ProgressBar

        if( set PlayerWidgetsMap [Player] = PlayerWidgets, PlayerUI := GetPlayerUI[Player]):
            PlayerUI.AddWidget(Canvas)

    InitRankUI(Player : player, Custom_Player : CustomPlayer, Rank_Settings : RankSettings): void=
        UpdateRank(Player, Custom_Player, Rank_Settings)

    UpdateRank(Player : player, Custom_Player : CustomPlayer, Rank_Settings : RankSettings):void=
        RankIndex := Custom_Player.PlayerRank
        if (Widgets := PlayerWidgetsMap[Player], NewRank := Rank_Settings.RankTypes[RankIndex], Image:= Rank_Settings.Images[RankIndex]):
            Widgets.ProgressBar.SetForegroundColor(NewRank.ForegroundColor)
            Widgets.ProgressBar.SetBackgroundColor(NewRank.BackgroundColor)
            Widgets.ProgressBar.SetRankText(NewRank.Name)
            Widgets.ProgressBar.SetImage(Image, vector2{X:= 540.0, Y:=500.0})
            UpdateProgress(Player, Custom_Player, Rank_Settings)

    UpdateProgress(Player : player, Custom_Player : CustomPlayer, Rank_Settings : RankSettings): void = 
        RankIndex := Custom_Player.PlayerRank
        if(Widgets := PlayerWidgetsMap[Player], CurrentRank := Rank_Settings.RankTypes[RankIndex]):
            if( NextRank := Rank_Settings.RankTypes[RankIndex +1]):
                Progress := 1.0* (Custom_Player.PlayerPoints - CurrentRank.PointsForRank) / (1.0* (NextRank.PointsForRank - CurrentRank.PointsForRank))
                if(Rank_Settings.PointsVisible = true):
                    ProgressText := "{Custom_Player.PlayerPoints}/{NextRank.PointsForRank}"
                    Widgets.ProgressBar.SetProgress(Progress, ProgressText)
                else:
                    Widgets.ProgressBar.SetProgress(Progress , "")
            else:
                Progress := 1.0
                if(Rank_Settings.PointsVisible = true):
                    ProgressText := "{Custom_Player.PlayerPoints}"
                    Widgets.ProgressBar.SetProgress(Progress, ProgressText)
                else:
                    Widgets.ProgressBar.SetProgress(Progress , "")
PlayerWidget := struct:
    Canvas : canvas
    ProgressBar : CustomProgressBar

CustomProgressBar := class:
    Width : float
    Heigth : float

    RankTextureBlock : texture_block = texture_block{DefaultImage := AllRanks.Unranked}
    ColorBlockForeground : color_block = color_block{}
    ColorBlockBackground : color_block = color_block{}
    RankTextBlock : text_block = text_block{DefaultTextColor := NamedColors.White}
    ProgressTextBlock : text_block = text_block{DefaultTextColor := NamedColors.White}

    var RootWidget : widget = color_block{}

    Init():void=
        ColorBlockForeground.SetDesiredSize(vector2{X:=Width,Y:=Heigth})
        ColorBlockBackground.SetDesiredSize(vector2{X:=Width,Y:=Heigth})
        set RootWidget = overlay:
            Slots := array:
                overlay_slot:
                    Widget := RankTextureBlock
                    HorizontalAlignment := horizontal_alignment.Center
                    Padding := margin{Right := 20.0, Top := -32.0}
                overlay_slot:
                    Widget := stack_box:
                        Orientation := orientation.Vertical
                        Slots := array:
                            stack_box_slot:
                                Widget := overlay:
                                    Slots := array:
                                        overlay_slot:
                                            Widget := ColorBlockBackground
                                            HorizontalAlignment := horizontal_alignment.Left
                                        overlay_slot:
                                            Widget := ColorBlockForeground
                                            HorizontalAlignment := horizontal_alignment.Left
                                        overlay_slot:
                                            Widget := ProgressTextBlock
                                            HorizontalAlignment := horizontal_alignment.Center

    SetProgress(InProgress : float, ProgressText : string) : void= 
        var NewProgress : float = 0.0
        if ( InProgress > 1.0) then set NewProgress = 1.0
        else if( InProgress < 0.0) then set NewProgress = 0.0
        else set NewProgress = InProgress

        NewWidth := NewProgress * Width
        ColorBlockForeground.SetDesiredSize(vector2{X:= NewWidth, Y := Heigth})
        SetProgressText(ProgressText)
                                        
    GetRootWidget(): widget = RootWidget 
    SetForegroundColor(Color : color):void= ColorBlockForeground.SetColor(Color)
    SetBackgroundColor(Color : color):void= ColorBlockBackground.SetColor(Color)
    SetRankText(String : string):void = RankTextBlock.SetText(StringToMessage(String))
    SetProgressText(String : string):void= ProgressTextBlock.SetText(StringToMessage(String))
    SetImage(NewImage :texture, NewSize : vector2):void=
        RankTextureBlock.SetImage(NewImage)
        RankTextureBlock.SetDesiredSize(NewSize)

AgentToMessage<localizes>(Agent:agent):message="{Agent}"
FloatToMessage<localizes>(String : string,Float : float):message="{String}{Float}"
IntToMessage<localizes>(String : string, Integer : int):message="{String}{Integer}"
StringsToMessage<localizes>(String1 : string, String2 : string):message = "{String1}{String2}"
StringToMessage<localizes>(String : string):message= "{String}"



Rank := class<concrete>:
    @editable Name : string = "Rank Name"
    @editable PointsForRank : int = 0
    @editable ForegroundColor : color = color{}
    @editable BackgroundColor : color = color{}

RankSettings := class<concrete>:
    @editable PointsVisible : logic = false
    @editable RankTypes : []Rank = array{}
    Images :[]texture = array:
        # Change the names to your rank images names
        AllRanks.Unranked
        AllRanks.Bronze1
        AllRanks.Bronze2
        AllRanks.Bronze3
        AllRanks.Silver1
        AllRanks.Silver2
        AllRanks.Silver3
        AllRanks.Gold1
        AllRanks.Gold2
        AllRanks.Gold3
        AllRanks.Plat1
        AllRanks.Plat2
        AllRanks.Plat3
        AllRanks.Diamond1
        AllRanks.Diamond2
        AllRanks.Diamond3
        AllRanks.Elite
        AllRanks.Champion
        AllRanks.Unreal
AllRanks<public> := module: