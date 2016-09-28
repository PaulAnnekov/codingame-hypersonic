import 'dart:io';
import 'dart:math';

List<List<String>> map = [];
int width;
int height;
Map<int, Map> players = {};
int range = 3;
int countdown = 8;

void main() {
    List inputs;
    inputs = stdin.readLineSync().split(' ');
    width = int.parse(inputs[0]);
    height = int.parse(inputs[1]);
    int myId = int.parse(inputs[2]);
    Point target, targetPos;
    // game loop
    while (true) {
        stderr.writeln('loop');
        map.clear();
        for (int i = 0; i < height; i++) {
            var a = stdin.readLineSync();
            stderr.writeln(a);
            map.add(a.split(''));
        }
        players.clear();
        BombsWatcher bombsWatcher = new BombsWatcher();
        int entities = int.parse(stdin.readLineSync());
        for (int i = 0; i < entities; i++) {
            inputs = stdin.readLineSync().split(' ');
            int entityType = int.parse(inputs[0]);
            int owner = int.parse(inputs[1]);
            Point pos = new Point(int.parse(inputs[2]), int.parse(inputs[3]));
            int param1 = int.parse(inputs[4]);
            int param2 = int.parse(inputs[5]);
            if (entityType==0) {
                players[owner] = {'pos': pos, 'bombs': param1, 'range': param2};
            } else if (entityType==1) {
                bombsWatcher.addBomb(pos, {'owner': owner, 'countdown': param1, 'range': param2});
            }
        }
        var action = null;
        var myLocation = players[myId]['pos']/*new Point(5,0)*/;
        stderr.writeln('before algo');
        var targetType = targetPos != null ? cellType(targetPos) : null;
        if (target != null && myLocation==target && players[myId]['bombs']>0 && targetType['box']) {
            stderr.writeln('BOMB!!!');
            bombsWatcher.addBomb(target, {'owner': myId, 'countdown': countdown, 'range': players[myId]['range']});
            action = 'BOMB';
            target = null;
        }
        // if no target or target box was already destroyed
        if (target == null || !targetType['box']) {
            stderr.writeln('searching');
            var spiralProcessor = new SpiralProcessor(map, myLocation);
            var box, boxes = {};
            var affectedBoxes = bombsWatcher.getAffectedBoxes();
            while ((box = spiralProcessor.getNext()) != null) {
                stderr.writeln('box near ${box}');
                if (affectedBoxes.contains(box))
                {
                    stderr.writeln("it's marked as 'to destroy'");
                    continue;
                }
                var path = AStar.path(myLocation, box);
                if (path == null)
                  continue;
                boxes[path.length] = {'target': path[1],
                    'pos': path[0]};
            }
            // the last box where we settled a bomb. no more boxes.
            if (boxes.isEmpty) {
                target = new Point(0, 0);
            } else {
                var distances = boxes.keys.toList();
                stderr.writeln('distances ${distances}');
                distances.sort();
                box = boxes[distances[0]];
                target = box['target'];
                targetPos = box['pos'];
                stderr.writeln('target ${target}');
                stderr.writeln('toDestroy ${targetPos}');
            }
        }
        print((action != null ? action : 'MOVE')+' ${target.x} ${target.y}');
        stderr.writeln('end');
    }
}

class BombsWatcher {
  Map<Point, Map> _bombs = {};
  static final List<List<int>> directions = [[1, 0], [0, 1], [-1, 0], [0, -1]];

  void addBomb(Point pos, Map info) {
    _bombs[pos] = info;
  }

  List<Point> _getAffectedBoxes(Point pos, Map info) {
    List<Point> boxes = [];
    directions.forEach((direction) {
      var i = 0;
      while (true) {
        var cell = new Point(pos.x+direction[0]*i, pos.y+direction[1]*i);
        if (isOutOfMap(cell.x, cell.y))
          break;
        var type = cellType(cell);
        // wall blocks fire
        if (type['wall'])
          break;
        if (type['box']) {
          stderr.writeln('to destroy cell ${cell} from ${pos} by dir ${direction}');
          boxes.add(cell);
          break;
        }
        i++;
      }
    });

    return boxes;
  }

  List<Point> getAffectedBoxes() {
    List<Point> boxes = [];
    _bombs.forEach((pos, info) {
      boxes.addAll(_getAffectedBoxes(pos, info));
    });
    return boxes;
  }
}

List<int> getPositionBetween(List<int> point1, List<int> point2) {
    return [(point1[0]-point2[0]).abs().toInt(),
        (point1[1]-point2[1]).abs().toInt()];
}

List<List<int>> getBoxesNear(List<int> point, int range) {
    List<List<int>> directions = [[0, 1], [1, 0], [0, -1], [-1, 0]];
    List<List<int>> boxes = [];
    for (var i = 1; i <= range; i++) {
        directions.forEach((direction) {
            if (!cellType(new Point(map[direction[0] * range], [direction[1] * range]))['box'])
                return;
            boxes.add([direction[0] * range, direction[1] * range]);
        });
    }
    return boxes;
}

class SpiralProcessor {
    Point _current;
    Point _point;
    int radius = 1;
    bool _isEnd = false;
    double _angle = 0.0;
    Map _cellsPerLoop = {};

    SpiralProcessor(List<List<String>> map, Point point) {
        _point = point;
    }

    Point getNext() {
        bool isFound = false;
        while (!_isEnd) {
            var _angleFactor = PI/2/(radius*2);
            _cellsPerLoop[radius] ??= 0;
            while (_angle < 2*PI) {
                var x = _point.x+_nearest(radius*cos(_angle)),
                    y = _point.y+_nearest(radius*sin(_angle));
                _angle += _angleFactor;
                if (isOutOfMap(x, y))
                    continue;
                _cellsPerLoop[radius]++;

                if (cellType(new Point(x, y))['box']) {
                    _current = new Point(x, y);
                    isFound = true;
                    break;
                }
            }
            if (_cellsPerLoop[radius] == 0)
                _isEnd = true;
            if (!isFound) {
                _angle = 0.0;
                radius++;
            } else {
                break;
            }
        }
        return !_isEnd ? _current : null;
    }

    int _nearest(double val) {
        if ((val - val.truncate()).abs() < 0.1)
            return val.truncate();
        return val < 0 ? val.floor() : val.ceil();
    }
}

bool isOutOfMap(int x, int y) {
  return x < 0 || y < 0 || y >= height || x >= width;
}

Map cellType(Point cell) {
    var val = map[cell.y][cell.x];
    return {
        'obstacle': val != '.',
        'box': int.parse(val, onError: (_) => null) != null,
        'free': val == '.',
        'wall': val == 'X'
    };
}

class AStar {
    static List<Point> path(Point from, Point to) {
        stderr.writeln('searching path');
        stderr.writeln(from);
        stderr.writeln(to);
        // game does not support diagonal moves
        var neighborX = [1, 0, -1, 0];
        var neighborY = [0, 1, 0, -1];
        Point current;
        List<Point> closedSet = [];
        List<Point> openSet = [from];
        Map<Point, Point> cameFrom = {};
        var gScore = {from: 0};
        var fScore = {from: from.distanceTo(to)};
        while (!openSet.isEmpty) {
            current = openSet.reduce((first, second)=>
            fScore[first] < fScore[second] ? first : second);
            if (current == to)
                return _getPath(cameFrom, current);
            openSet.remove(current);
            closedSet.add(current);
            for (var i = 0; i < 4; i++) {
                var x = current.x+neighborX[i];
                var y = current.y+neighborY[i];
                var neighbor = new Point(x, y);
                if (isOutOfMap(x, y))
                    continue;
                var type = cellType(neighbor);
                // boxes are obstacles, but only when it's not target box
                if (neighbor != to && type['obstacle'])
                    continue;
                if (closedSet.contains(neighbor))
                    continue;
                var tentativeGScore = gScore[current] + 1;
                if (!openSet.contains(neighbor))
                    openSet.add(neighbor);
                else if (tentativeGScore >= gScore[neighbor])
                    continue;
                cameFrom[neighbor] = current;
                gScore[neighbor] = tentativeGScore;
                fScore[neighbor] = gScore[neighbor] + neighbor.distanceTo(to);
            }
        }
        return null;
    }

    static List<Point> _getPath(Map cameFrom, Point current) {
        var totalPath = [current];
        while (cameFrom.containsKey(current)) {
            current = cameFrom[current];
            totalPath.add(current);
        }
        return totalPath;
    }
}