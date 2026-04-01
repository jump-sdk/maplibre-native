#include <mbgl/renderer/render_tile.hpp>
#include <mbgl/renderer/source_state.hpp>
#include <mbgl/style/conversion_impl.hpp>
#include <mbgl/util/instrumentation.hpp>
#include <mbgl/util/logging.hpp>

namespace mbgl {

void SourceFeatureState::updateState(const std::optional<std::string>& sourceLayerID,
                                     const std::string& featureID,
                                     const FeatureState& newState) {
    std::string sourceLayer = sourceLayerID.value_or(std::string());
    for (const auto& state : newState) {
        auto& layerStates = stateChanges[sourceLayer];
        auto& featureStates = layerStates[featureID];
        featureStates[state.first] = state.second;
    }
}

void SourceFeatureState::getState(FeatureState& result,
                                  const std::optional<std::string>& sourceLayerID,
                                  const std::string& featureID) const {
    std::string sourceLayer = sourceLayerID.value_or(std::string());
    FeatureState current;
    FeatureState changes;
    auto layerStates = currentStates.find(sourceLayer);
    if (layerStates != currentStates.end()) {
        const auto currentStateEntry = layerStates->second.find(featureID);
        if (currentStateEntry != layerStates->second.end()) {
            current = currentStateEntry->second;
        }
    }

    layerStates = stateChanges.find(sourceLayer);
    if (layerStates != stateChanges.end()) {
        const auto stateChangesEntry = layerStates->second.find(featureID);
        if (stateChangesEntry != layerStates->second.end()) {
            changes = stateChangesEntry->second;
        }
    }
    result = std::move(changes);
    result.insert(current.begin(), current.end());
}

void SourceFeatureState::coalesceChanges(std::vector<RenderTile>& tiles) {
    MLN_TRACE_FUNC();

    // Process deletedStates BEFORE stateChanges so that a remove+set in the same
    // frame results in the set winning. Previously, deletes were processed after sets,
    // causing changes[sourceLayer] to be overwritten with empty state.
    for (const auto& layerStatesEntry : deletedStates) {
        const auto& sourceLayer = layerStatesEntry.first;

        if (deletedStates[sourceLayer].empty()) {
            for (const auto& featureStatesEntry : currentStates[sourceLayer]) {
                const auto& featureID = featureStatesEntry.first;
                currentStates[sourceLayer][featureID] = {};
            }
        } else {
            for (const auto& feature : deletedStates[sourceLayer]) {
                const auto& featureID = feature.first;
                bool deleteWholeFeatureState = deletedStates[sourceLayer][featureID].empty();
                if (deleteWholeFeatureState) {
                    currentStates[sourceLayer][featureID] = {};
                } else {
                    for (const auto& stateEntry : deletedStates[sourceLayer][featureID]) {
                        currentStates[sourceLayer][featureID].erase(stateEntry.first);
                    }
                }
            }
        }
    }

    // Now process stateChanges — these take precedence over deletes.
    for (const auto& layerStatesEntry : stateChanges) {
        const auto& sourceLayer = layerStatesEntry.first;
        for (const auto& featureStatesEntry : stateChanges[sourceLayer]) {
            const auto& featureID = featureStatesEntry.first;
            for (const auto& stateEntry : stateChanges[sourceLayer][featureID]) {
                const auto& stateKey = stateEntry.first;
                const auto& stateVal = stateEntry.second;

                auto currentState = currentStates[sourceLayer][featureID].find(stateKey);
                if (currentState != currentStates[sourceLayer][featureID].end()) {
                    currentState->second = stateVal;
                } else {
                    currentStates[sourceLayer][featureID].insert(std::make_pair(stateKey, stateVal));
                }
            }
        }
    }

    stateChanges.clear();
    deletedStates.clear();

    // Build the full current state to send to tiles.
    if (currentStates.empty()) {
        return;
    }

    for (auto& tile : tiles) {
        tile.setFeatureState(currentStates);
    }
}

void SourceFeatureState::removeState(const std::optional<std::string>& sourceLayerID,
                                     const std::optional<std::string>& featureID,
                                     const std::optional<std::string>& stateKey) {
    std::string sourceLayer = sourceLayerID.value_or(std::string());

    bool sourceLayerDeleted = deletedStates.contains(sourceLayer) && deletedStates[sourceLayer].empty();
    if (sourceLayerDeleted) {
        return;
    }

    if (stateKey && featureID) {
        if (!deletedStates.contains(sourceLayer) && !deletedStates[sourceLayer].contains(*featureID)) {
            deletedStates[sourceLayer][*featureID][*stateKey] = {};
        }
    } else if (featureID) {
        bool updateInQueue = stateChanges.contains(sourceLayer) && stateChanges[sourceLayer].contains(*featureID);
        if (updateInQueue) {
            for (const auto& changeEntry : stateChanges[sourceLayer][*featureID]) {
                deletedStates[sourceLayer][*featureID][changeEntry.first] = {};
            }
        } else {
            deletedStates[sourceLayer][*featureID] = {};
        }
    } else {
        deletedStates[sourceLayer] = {};
    }
}

} // namespace mbgl
