import 'spec.dart';

void main() {
  const child = Node(
    name: 'child',
    metadata: {'owner': 'team'},
  );
  const root = Node(
    name: 'root',
    children: [child],
  );
  const sameRoot = Node(
    name: 'root',
    children: [Node(name: 'child', metadata: {'owner': 'team'})],
  );

  assert(root.children!.first.metadata!['owner'] == 'team');
  assert(root == sameRoot && root.hashCode == sameRoot.hashCode);
  assert(root.copyWith(children: null).children == null);
}
