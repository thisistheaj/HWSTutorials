//
//  GameScene.swift
//  Project17
//
//  Created by Anthony John Beckner on 12/15/15.
//  Copyright (c) 2015 ajbeckner. All rights reserved.
//

import SpriteKit
import AVFoundation

enum ForceBomb {
    case Never, Always, Default
}

enum SequenceType: Int {
    case OneNoBomb, One, TwoWithOneBomb, Two, Three, Four, Chain, FastChain
}

class GameScene: SKScene {
    
    var popupTime = 0.9
    var sequence: [SequenceType]!
    var sequencePosition = 0
    var chainDelay = 3.0
    var nextSequenceQueued = true
    
    //model and data used for
    var gameScore: SKLabelNode!
    var score: Int = 0 {
        didSet {
            gameScore.text = "Score: \(score)"
        }
    }
    
    //stores data about the slices, used to draw slices and as model for gameplay
    var activeSlicePoints = [CGPoint]()

    //two different nodes that will be drawn as lines
    //they will be on top of each other with the bckgd being thicker
    var activeSliceBG: SKShapeNode!
    var activeSliceFG: SKShapeNode!
    
    //bool used to prevent multiple slice sounds happening at once
    var swooshSoundActive = false
    
    //vars needed to display lives and lost lives
    var livesImages = [SKSpriteNode]()
    var lives = 3
    
    //var used to keep track of enemies
    var activeEnemies = [SKSpriteNode]()

    var bombSoundEffect: AVAudioPlayer!

    var gameEnded = false

    override func didMoveToView(view: SKView) {
        let background = SKSpriteNode(imageNamed: "sliceBackground")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .Replace
        background.zPosition = -1
        addChild(background)
        
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.speed = 0.85
        
        createScore()
        createLives()
        createSlices()
        
        sequence = [.OneNoBomb, .OneNoBomb, .TwoWithOneBomb, .TwoWithOneBomb, .Three, .One, .Chain]
        
        for _ in 0 ... 1000 {
            let nextSequence = SequenceType(rawValue: randomInt(min: 2, max: 7))!
            sequence.append(nextSequence)
        }
        
        RunAfterDelay(2) { [unowned self] in
            self.tossEnemies()
        }
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesBegan(touches, withEvent: event)
        
        // 1
        activeSlicePoints.removeAll(keepCapacity: true)
        
        // 2
        if let touch = touches.first {
            let location = touch.locationInNode(self)
            activeSlicePoints.append(location)
            
            // 3
            redrawActiveSlice()
            
            // 4
            activeSliceBG.removeAllActions()
            activeSliceFG.removeAllActions()
            
            // 5
            activeSliceBG.alpha = 1
            activeSliceFG.alpha = 1
        }
    }
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        guard let touch = touches.first else { return }
        if gameEnded {
            return
        }

        
        let location = touch.locationInNode(self)
        
        activeSlicePoints.append(location)
        redrawActiveSlice()
        if !swooshSoundActive {
            playSwooshSound()
        }
        
        let nodes = nodesAtPoint(location)
        
        for node in nodes {
            if node.name == "enemy" {
                // 1
                let emitter = SKEmitterNode(fileNamed: "sliceHitEnemy.sks")!
                emitter.position = node.position
                addChild(emitter)
                
                // 2
                node.name = ""
                
                // 3
                node.physicsBody!.dynamic = false
                
                // 4
                let scaleOut = SKAction.scaleTo(0.001, duration:0.2)
                let fadeOut = SKAction.fadeOutWithDuration(0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                
                // 5
                let seq = SKAction.sequence([group, SKAction.removeFromParent()])
                node.runAction(seq)
                
                // 6
                ++score
                
                // 7
                let index = activeEnemies.indexOf(node as! SKSpriteNode)!
                activeEnemies.removeAtIndex(index)
                
                // 8
                runAction(SKAction.playSoundFileNamed("whack.caf", waitForCompletion: false))
            } else if node.name == "bomb" {
                let emitter = SKEmitterNode(fileNamed: "sliceHitBomb.sks")!
                emitter.position = node.parent!.position
                addChild(emitter)
                
                node.name = ""
                node.parent!.physicsBody!.dynamic = false
                
                let scaleOut = SKAction.scaleTo(0.001, duration:0.2)
                let fadeOut = SKAction.fadeOutWithDuration(0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                
                let seq = SKAction.sequence([group, SKAction.removeFromParent()])
                
                node.parent!.runAction(seq)
                
                let index = activeEnemies.indexOf(node.parent as! SKSpriteNode)!
                activeEnemies.removeAtIndex(index)
                
                runAction(SKAction.playSoundFileNamed("explosion.caf", waitForCompletion: false))
                endGame(triggeredByBomb: true)            }
        }
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        activeSliceBG.runAction(SKAction.fadeOutWithDuration(0.25))
        activeSliceFG.runAction(SKAction.fadeOutWithDuration(0.25))
    }
    
    override func touchesCancelled(touches: Set<UITouch>?, withEvent event: UIEvent?) {
        if let touches = touches {
            touchesEnded(touches, withEvent: event)
        }
    }
    
    override func update(currentTime: CFTimeInterval) {
        if activeEnemies.count > 0 {
            for node in activeEnemies {
                if node.position.y < -140 {
                    node.removeAllActions()
                    
                    if node.name == "enemy" {
                        node.name = ""
                        subtractLife()
                        
                        node.removeFromParent()
                        
                        if let index = activeEnemies.indexOf(node) {
                            activeEnemies.removeAtIndex(index)
                        }
                    } else if node.name == "bombContainer" {
                        node.name = ""
                        node.removeFromParent()
                        
                        if let index = activeEnemies.indexOf(node) {
                            activeEnemies.removeAtIndex(index)
                        }
                    }
                }
            }
        } else {
            if !nextSequenceQueued {
                RunAfterDelay(popupTime) { [unowned self] in
                    self.tossEnemies()
                }
                
                nextSequenceQueued = true
            }
        }

        var bombCount = 0
        
        for node in activeEnemies {
            if node.name == "bombContainer" {
                ++bombCount
                break
            }

        }
        
        if bombCount == 0 {
            // no bombs – stop the fuse sound!
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }
        }
        
    }
    
    func redrawActiveSlice() {
        // 1
        if activeSlicePoints.count < 2 {
            activeSliceBG.path = nil
            activeSliceFG.path = nil
            return
        }
        
        // 2
        while activeSlicePoints.count > 3 {
            activeSlicePoints.removeAtIndex(0)
        }
        
        // 3
        let path = UIBezierPath()
        path.moveToPoint(activeSlicePoints[0])
        
        for var i = 1; i < activeSlicePoints.count; ++i {
            path.addLineToPoint(activeSlicePoints[i])
        }
        
        // 4
        activeSliceBG.path = path.CGPath
        activeSliceFG.path = path.CGPath
    }
    
    func createScore() {
        gameScore = SKLabelNode(fontNamed: "Chalkduster")
        gameScore.text = "Score: 0"
        gameScore.horizontalAlignmentMode = .Left
        gameScore.fontSize = 48
        
        addChild(gameScore)
        
        gameScore.position = CGPoint(x: 8, y: 8)
    }
    
    func createLives() {
        for i in 0 ..< 3 {
            let spriteNode = SKSpriteNode(imageNamed: "sliceLife")
            spriteNode.position = CGPoint(x: CGFloat(834 + (i * 70)), y: 720)
            addChild(spriteNode)
            
            livesImages.append(spriteNode)
        }
    }
    
    func createSlices() {
        activeSliceBG = SKShapeNode()
        activeSliceBG.zPosition = 2
        
        activeSliceFG = SKShapeNode()
        activeSliceFG.zPosition = 2
        
        activeSliceBG.strokeColor = UIColor(red: 1, green: 0.9, blue: 0, alpha: 1)
        activeSliceBG.lineWidth = 9
        
        activeSliceFG.strokeColor = UIColor.whiteColor()
        activeSliceFG.lineWidth = 5
        
        addChild(activeSliceBG)
        addChild(activeSliceFG)
    }
    
    func createEnemy(forceBomb forceBomb: ForceBomb = .Default) {
        var enemy: SKSpriteNode
        
        var enemyType = randomInt(min: 0, max: 6)
        
        if forceBomb == .Never {
            enemyType = 1
        } else if forceBomb == .Always {
            enemyType = 0
        }
        
        if enemyType == 0 {
            // 1
            enemy = SKSpriteNode()
            enemy.zPosition = 1
            enemy.name = "bombContainer"
            
            // 2
            let bombImage = SKSpriteNode(imageNamed: "sliceBomb")
            bombImage.name = "bomb"
            enemy.addChild(bombImage)
            
            // 3
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }
            
            // 4
            let path = NSBundle.mainBundle().pathForResource("sliceBombFuse.caf", ofType:nil)!
            let url = NSURL(fileURLWithPath: path)
            let sound = try! AVAudioPlayer(contentsOfURL: url)
            bombSoundEffect = sound
            sound.play()
            
            // 5
            let emitter = SKEmitterNode(fileNamed: "sliceFuse.sks")!
            emitter.position = CGPoint(x: 76, y: 64)
            enemy.addChild(emitter)        } else {
            enemy = SKSpriteNode(imageNamed: "penguin")
            runAction(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemy"
        }
        
        // 1
        let randomPosition = CGPoint(x: randomInt(min: 64, max: 960), y: -128)
        enemy.position = randomPosition
        
        // 2
        let    randomAngularVelocity = CGFloat(randomInt(min: -6, max: 6)) / 2.0
        var randomXVelocity = 0
        
        // 3
        if randomPosition.x < 256 {
            randomXVelocity = randomInt(min: 8, max: 15)
        } else if randomPosition.x < 512 {
            randomXVelocity = randomInt(min: 3, max: 5)
        } else if randomPosition.x < 768 {
            randomXVelocity = -randomInt(min: 3, max: 5)
        } else {
            randomXVelocity = -randomInt(min: 8, max: 15)
        }
        
        // 4
        let randomYVelocity = randomInt(min: 24, max: 32)
        
        // 5
        enemy.physicsBody = SKPhysicsBody(circleOfRadius: 64)
        enemy.physicsBody!.velocity = CGVector(dx: randomXVelocity * 40, dy: randomYVelocity * 40)
        enemy.physicsBody!.angularVelocity = randomAngularVelocity
        enemy.physicsBody!.collisionBitMask = 0
        
        
        addChild(enemy)
        activeEnemies.append(enemy)
    }
    
    func playSwooshSound() {
        swooshSoundActive = true
        
        let randomNumber = randomInt(min: 1, max: 3)
        let soundName = "swoosh\(randomNumber).caf"
        
        let swooshSound = SKAction.playSoundFileNamed(soundName, waitForCompletion: true)
        
        runAction(swooshSound) { [unowned self] in
            self.swooshSoundActive = false
        }
    }
    
    func randomInt(min min: Int, max:Int) -> Int {
        return min + Int(arc4random_uniform(UInt32(max - min + 1)))
    }
    
    func tossEnemies() {
        if gameEnded {
            return
        }

        popupTime *= 0.991
        chainDelay *= 0.99
        physicsWorld.speed *= 1.02
        
        let sequenceType = sequence[sequencePosition]
        
        switch sequenceType {
        case .OneNoBomb:
            createEnemy(forceBomb: .Never)
            
        case .One:
            createEnemy()
            
        case .TwoWithOneBomb:
            createEnemy(forceBomb: .Never)
            createEnemy(forceBomb: .Always)
            
        case .Two:
            createEnemy()
            createEnemy()
            
        case .Three:
            createEnemy()
            createEnemy()
            createEnemy()
            
        case .Four:
            createEnemy()
            createEnemy()
            createEnemy()
            createEnemy()
            
        case .Chain:
            createEnemy()
            
            RunAfterDelay(chainDelay / 5.0) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 2) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 3) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 4) { [unowned self] in self.createEnemy() }
            
        case .FastChain:
            createEnemy()
            
            RunAfterDelay(chainDelay / 10.0) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 2) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 3) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 4) { [unowned self] in self.createEnemy() }
        }
        
        
        ++sequencePosition
        
        nextSequenceQueued = false
    }

    func subtractLife() {
        --lives
        
        runAction(SKAction.playSoundFileNamed("wrong.caf", waitForCompletion: false))
        
        var life: SKSpriteNode
        
        if lives == 2 {
            life = livesImages[0]
        } else if lives == 1 {
            life = livesImages[1]
        } else {
            life = livesImages[2]
            endGame(triggeredByBomb: false)
        }
        
        life.texture = SKTexture(imageNamed: "sliceLifeGone")
        
        life.xScale = 1.3
        life.yScale = 1.3
        life.runAction(SKAction.scaleTo(1, duration:0.1))
    }
    
    func endGame(triggeredByBomb triggeredByBomb: Bool) {
        if gameEnded {
            return
        }
        
        gameEnded = true
        physicsWorld.speed = 0
        userInteractionEnabled = false
        
        if bombSoundEffect != nil {
            bombSoundEffect.stop()
            bombSoundEffect = nil
        }
        
        if triggeredByBomb {
            livesImages[0].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[1].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[2].texture = SKTexture(imageNamed: "sliceLifeGone")
        }
    }

}
