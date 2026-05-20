import Foundation

final class CustomActionIndexer {
    func load(actions: [CustomAction]) -> [LaunchItem] {
        actions.compactMap { action in
            let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = action.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !command.isEmpty,
                  let url = URL(string: "bucky-action://\(action.id.uuidString.lowercased())") else {
                return nil
            }

            return LaunchItem(
                title: name,
                subtitle: command,
                url: url,
                launchTarget: .shellCommand(command),
                category: .action,
                searchText: normalized("\(name) \(command)")
            )
        }
    }
}
